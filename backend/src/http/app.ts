import { createHash } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { RegionUnavailableError, UnknownRegionError, UpstreamError } from '../providers/provider.ts';
import { UnknownGroupError, type ScheduleService } from '../service.ts';

type Json = Record<string, unknown> | unknown[];

interface Reply {
  status: number;
  body: Json;
  /** Seconds clients and CDNs may cache the reply. */
  maxAge?: number;
}

const GROUP = /^\d{1,2}\.\d{1,2}$/;
const REGION = /^[a-z0-9-]{1,40}$/;

/**
 * Routes:
 *   GET /health
 *   GET /v1/regions
 *   GET /v1/regions/:region/groups
 *   GET /v1/regions/:region/schedule?groups=1.1,3.2   (all groups when omitted)
 */
export function createApp(service: ScheduleService, log: (line: string) => void = () => {}) {
  async function route(method: string, url: URL): Promise<Reply> {
    if (method !== 'GET' && method !== 'HEAD') return error(405, 'method_not_allowed', 'Only GET is supported');

    const path = url.pathname.replace(/\/+$/, '') || '/';
    if (path === '/health') return { status: 200, body: { ok: true, source: service.source } };
    if (path === '/v1/regions') return { status: 200, body: { regions: service.regions() }, maxAge: 3600 };

    const m = path.match(/^\/v1\/regions\/([^/]+)\/(groups|schedule)$/);
    if (!m) return error(404, 'not_found', `No route for ${path}`);
    const [, region = '', resource] = m;
    if (!REGION.test(region)) return error(400, 'bad_region', 'Region id must be a lowercase slug');

    if (resource === 'groups') {
      return { status: 200, body: { region, groups: await service.groups(region) }, maxAge: 300 };
    }

    const raw = url.searchParams.get('groups');
    const groups = raw ? [...new Set(raw.split(',').map((g) => g.trim()).filter(Boolean))] : [];
    const bad = groups.filter((g) => !GROUP.test(g));
    if (bad.length) return error(400, 'bad_group', `Invalid group id(s): ${bad.join(', ')}`);
    if (groups.length > 20) return error(400, 'too_many_groups', 'Ask for at most 20 groups at once');

    const result = await service.schedules(region, groups);
    return { status: 200, body: result as unknown as Json, maxAge: result.stale ? 30 : 60 };
  }

  return async function handler(req: IncomingMessage, res: ServerResponse) {
    const started = performance.now();
    const url = new URL(req.url ?? '/', 'http://localhost');
    let reply: Reply;
    try {
      reply = await route(req.method ?? 'GET', url);
    } catch (err) {
      reply = toErrorReply(err);
      if (reply.status >= 500) log(`error ${url.pathname}: ${err instanceof Error ? err.stack : String(err)}`);
    }

    const payload = JSON.stringify(reply.body);
    const etag = `"${createHash('sha1').update(payload).digest('base64url')}"`;
    const headers: Record<string, string> = {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': '*',
      'cache-control': reply.status === 200 && reply.maxAge ? `public, max-age=${reply.maxAge}` : 'no-store',
      etag,
    };

    if (reply.status === 200 && req.headers['if-none-match'] === etag) {
      res.writeHead(304, headers).end();
    } else {
      res.writeHead(reply.status, { ...headers, 'content-length': String(Buffer.byteLength(payload)) });
      res.end(req.method === 'HEAD' ? undefined : payload);
    }
    log(`${req.method} ${url.pathname}${url.search} ${res.statusCode} ${(performance.now() - started).toFixed(1)}ms`);
  };
}

function error(status: number, code: string, message: string): Reply {
  return { status, body: { error: { code, message } } };
}

function toErrorReply(err: unknown): Reply {
  if (err instanceof UnknownRegionError) return error(404, 'unknown_region', err.message);
  if (err instanceof RegionUnavailableError) return error(404, 'region_unavailable', 'There is no open schedule source for this region yet');
  if (err instanceof UnknownGroupError) return error(404, 'unknown_group', err.message);
  if (err instanceof UpstreamError) return error(502, 'upstream_unavailable', 'The schedule source is unavailable, try again later');
  return error(500, 'internal', 'Something went wrong');
}
