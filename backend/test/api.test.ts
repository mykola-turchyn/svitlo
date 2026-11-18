import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, describe, it } from 'node:test';
import { TtlCache } from '../src/cache.ts';
import { createApp } from '../src/http/app.ts';
import { DemoProvider } from '../src/providers/demo.ts';
import { UpstreamError, type ScheduleProvider } from '../src/providers/provider.ts';
import { compareGroups, ScheduleService } from '../src/service.ts';

const NOW = new Date('2026-11-17T12:20:00Z');
let server: Server;
let base = '';

before(async () => {
  const service = new ScheduleService(new DemoProvider({ now: () => NOW }), { now: () => NOW });
  server = createServer(createApp(service));
  await new Promise<void>((resolve) => server.listen(0, resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => new Promise<void>((resolve) => server.close(() => resolve())));

const get = (path: string, headers: Record<string, string> = {}) => fetch(base + path, { headers });

describe('HTTP API', () => {
  it('answers health checks', async () => {
    const res = await get('/health');
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { ok: true, source: 'demo' });
  });

  it('lists regions', async () => {
    const body = await (await get('/v1/regions')).json();
    assert.ok(body.regions.some((r: { id: string }) => r.id === 'kyiv'));
  });

  it('lists groups in numeric order', async () => {
    const body = await (await get('/v1/regions/kyiv/groups')).json();
    assert.equal(body.groups[0], '1.1');
    assert.equal(body.groups.at(-1), '6.2');
  });

  it('returns schedules with the current state for requested groups', async () => {
    const res = await get('/v1/regions/kyiv/schedule?groups=3.2,1.1,3.2');
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.deepEqual(body.groups.map((g: { group: string }) => g.group), ['3.2', '1.1']);
    assert.deepEqual(body.now, { date: '2026-11-17', minute: 14 * 60 + 20 });
    assert.equal(typeof body.groups[0].current.isOn, 'boolean');
    assert.equal(res.headers.get('cache-control'), 'public, max-age=60');
  });

  it('supports conditional requests', async () => {
    const first = await get('/v1/regions/kyiv/groups');
    const again = await get('/v1/regions/kyiv/groups', { 'if-none-match': first.headers.get('etag')! });
    assert.equal(again.status, 304);
  });

  it('rejects bad input with JSON errors', async () => {
    assert.equal((await get('/v1/regions/kyiv/schedule?groups=abc')).status, 400);
    const partial = await (await get('/v1/regions/kyiv/schedule?groups=1.1,9.9')).json();
    assert.deepEqual(partial.groups.map((g: { group: string }) => g.group), ['1.1']);
    assert.deepEqual(partial.missing, ['9.9']);
    const unknownGroup = await get('/v1/regions/kyiv/schedule?groups=9.9');
    assert.equal(unknownGroup.status, 404);
    assert.equal((await unknownGroup.json()).error.code, 'unknown_group');
    assert.equal((await get('/v1/regions/atlantis/groups')).status, 404);
    const unavailable = await get('/v1/regions/vinnytsia/groups');
    assert.equal(unavailable.status, 404);
    assert.equal((await unavailable.json()).error.code, 'region_unavailable');
    assert.equal((await get('/nope')).status, 404);
  });
});

describe('ScheduleService', () => {
  it('serves the last good data when upstream fails', async () => {
    let clock = NOW.getTime();
    let fail = false;
    const demo = new DemoProvider({ now: () => NOW });
    const flaky: ScheduleProvider = {
      name: 'flaky',
      regions: () => demo.regions(),
      fetchRegion: async (id) => {
        if (fail) throw new UpstreamError('down');
        return demo.fetchRegion(id);
      },
    };
    const service = new ScheduleService(flaky, { ttlMs: 1000, maxStaleMs: 10_000, now: () => new Date(clock) });
    assert.equal((await service.schedules('kyiv', ['1.1'])).stale, false);

    fail = true;
    clock += 5000;
    assert.equal((await service.schedules('kyiv', ['1.1'])).stale, true);

    clock += 20_000;
    await assert.rejects(service.schedules('kyiv', ['1.1']), UpstreamError);
  });

  it('sorts groups numerically', () => {
    assert.deepEqual(['10.1', '2.2', '2.1', '1.2'].sort(compareGroups), ['1.2', '2.1', '2.2', '10.1']);
  });
});

describe('TtlCache', () => {
  it('shares one upstream call between concurrent requests', async () => {
    let calls = 0;
    const cache = new TtlCache<number>({ ttlMs: 1000, maxStaleMs: 1000 });
    const load = async () => {
      calls += 1;
      await new Promise((r) => setTimeout(r, 10));
      return 42;
    };
    const [a, b] = await Promise.all([cache.get('k', load), cache.get('k', load)]);
    assert.equal(calls, 1);
    assert.equal(a.value, b.value);
  });
});
