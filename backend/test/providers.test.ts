import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { DemoProvider } from '../src/providers/demo.ts';
import { parseGpv } from '../src/providers/gpv.ts';
import { LiveProvider } from '../src/providers/live.ts';
import { RegionUnavailableError, UnknownRegionError, UpstreamError } from '../src/providers/provider.ts';
import { parsePlannedOutages } from '../src/providers/yasno.ts';

const fixture = JSON.parse(readFileSync(new URL('./fixtures/yasno-planned.json', import.meta.url), 'utf8'));
const gpvFixture = JSON.parse(readFileSync(new URL('./fixtures/gpv.json', import.meta.url), 'utf8'));
const NOW = new Date('2026-11-17T12:20:00Z');

describe('parsePlannedOutages', () => {
  const groups = parsePlannedOutages('kyiv', fixture, NOW);

  it('keeps only group keys', () => {
    assert.deepEqual([...groups.keys()], ['1.1', '3.2']);
  });

  it('maps slot types and skips NotPlanned', () => {
    assert.deepEqual(groups.get('1.1')!.today.slots, [
      { start: 0, end: 240, kind: 'off' },
      { start: 720, end: 960, kind: 'off' },
      { start: 960, end: 1020, kind: 'maybe' },
    ]);
  });

  it('merges adjacent outages and maps day status', () => {
    const g = groups.get('3.2')!;
    assert.deepEqual(g.today.slots[0], { start: 480, end: 720, kind: 'off' });
    assert.equal(g.today.date, '2026-11-17');
    assert.equal(groups.get('1.1')!.tomorrow.status, 'waiting');
    assert.equal(g.updatedAt, '2026-11-17T10:05:00+00:00');
  });

  it('rejects payloads without groups', () => {
    assert.throws(() => parsePlannedOutages('kyiv', { foo: 1 }, NOW), UpstreamError);
    assert.throws(() => parsePlannedOutages('kyiv', [], NOW), UpstreamError);
  });
});

describe('parseGpv', () => {
  const groups = parseGpv('zhytomyr', gpvFixture, NOW);

  it('reads GPV groups and ignores other keys', () => {
    assert.deepEqual([...groups.keys()].sort(), ['1.1', '2.1']);
  });

  it('turns hourly values into merged slots, including half hours and possible outages', () => {
    assert.deepEqual(groups.get('1.1')!.today.slots, [
      { start: 0, end: 180, kind: 'off' },
      { start: 210, end: 240, kind: 'off' },
      { start: 660, end: 690, kind: 'off' },
      { start: 720, end: 780, kind: 'maybe' },
      { start: 1140, end: 1170, kind: 'maybe' },
    ]);
    assert.equal(groups.get('1.1')!.today.date, '2026-11-17');
    assert.deepEqual(groups.get('1.1')!.tomorrow.slots, [{ start: 0, end: 120, kind: 'off' }]);
  });

  it('marks days without data as "none" instead of "no outages"', () => {
    const g = groups.get('2.1')!;
    assert.equal(g.today.status, 'scheduled');
    assert.equal(g.tomorrow.status, 'none');
    assert.equal(g.updatedAt, '2026-11-17T17:38:31.392Z');
  });

  it('rejects files without fact data', () => {
    assert.throws(() => parseGpv('x', { regionId: 'x' }, NOW), UpstreamError);
  });
});

describe('LiveProvider', () => {
  const respond = (body: unknown) => async () => new Response(JSON.stringify(body), { status: 200 });

  it('lists every oblast, marking those without a source', () => {
    const regions = new LiveProvider().regions();
    assert.ok(regions.length >= 25);
    assert.equal(regions.find((r) => r.id === 'lviv')?.available, true);
    assert.equal(regions.find((r) => r.id === 'vinnytsia')?.available, false);
  });

  it('routes Kyiv to the Yasno planned-outages endpoint', async () => {
    let called = '';
    const provider = new LiveProvider({ now: () => NOW, fetch: async (url) => { called = url; return respond(fixture)(); } });
    const result = await provider.fetchRegion('kyiv');
    assert.match(called, /\/regions\/25\/dsos\/902\/planned-outages$/);
    assert.equal(result.size, 2);
  });

  it('routes oblenergo regions to their GPV JSON file', async () => {
    let called = '';
    const provider = new LiveProvider({ now: () => NOW, fetch: async (url) => { called = url; return respond(gpvFixture)(); } });
    const result = await provider.fetchRegion('zhytomyr');
    assert.match(called, /OE_OUTAGE_DATA\/main\/data\/Zhytomyroblenergo\.json$/);
    assert.equal(result.get('1.1')!.region, 'zhytomyr');
  });

  it('wraps HTTP and network failures', async () => {
    const failing = new LiveProvider({ fetch: async () => new Response('nope', { status: 503 }) });
    await assert.rejects(failing.fetchRegion('kyiv'), UpstreamError);
    await assert.rejects(failing.fetchRegion('lviv'), UpstreamError);
    const offline = new LiveProvider({ fetch: async () => { throw new TypeError('fetch failed'); } });
    await assert.rejects(offline.fetchRegion('odesa'), UpstreamError);
  });

  it('rejects unknown and unavailable regions without calling upstream', async () => {
    const provider = new LiveProvider({ fetch: async () => assert.fail('should not fetch') });
    await assert.rejects(provider.fetchRegion('atlantis'), UnknownRegionError);
    await assert.rejects(provider.fetchRegion('vinnytsia'), RegionUnavailableError);
  });
});

describe('DemoProvider', () => {
  it('is deterministic and covers all demo groups', async () => {
    const provider = new DemoProvider({ now: () => NOW });
    const a = await provider.fetchRegion('kyiv');
    const b = await provider.fetchRegion('kyiv');
    assert.equal(a.size, 12);
    assert.deepEqual(a.get('3.2'), b.get('3.2'));
    assert.equal(a.get('1.1')!.tomorrow.date, '2026-11-18');
  });
});
