import { normalizeSlots, type DaySchedule, type GroupSchedule, type Slot } from '../domain/schedule.ts';
import { addDays, kyivTime } from '../domain/time.ts';
import { UpstreamError } from './provider.ts';

/**
 * Hourly outage schedules ("графік погодинних відключень", ГПВ) in the JSON shape DTEK uses on its sites
 * and the community mirrors copy:
 *
 * { regionId, lastUpdated, fact: { today: <unix>, update: "17.11.2026 19:30",
 *   data: { "<unix of Kyiv midnight>": { "GPV1.1": { "1": "yes", …, "24": "no" }, … } } } }
 *
 * Hour "1" is 00:00–01:00. Values: yes (power), no (outage), first / second (outage in the first or
 * second half of the hour), maybe / mfirst / msecond (possible outage, whole hour or half).
 */
const HALF: Record<string, { kind: Slot['kind']; part: 'all' | 'first' | 'second' }> = {
  no: { kind: 'off', part: 'all' },
  first: { kind: 'off', part: 'first' },
  second: { kind: 'off', part: 'second' },
  maybe: { kind: 'maybe', part: 'all' },
  mfirst: { kind: 'maybe', part: 'first' },
  msecond: { kind: 'maybe', part: 'second' },
};

const GROUP_KEY = /^GPV(\d{1,2}\.\d{1,2})$/;

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

export async function fetchGpv(
  url: string,
  regionId: string,
  options: { fetch?: FetchFn; timeoutMs?: number; signal?: AbortSignal; now?: Date } = {},
): Promise<Map<string, GroupSchedule>> {
  const fetchFn = options.fetch ?? ((input, init) => fetch(input, init));
  const timeout = AbortSignal.timeout(options.timeoutMs ?? 8000);
  let res: Response;
  try {
    res = await fetchFn(url, {
      headers: { accept: 'application/json' },
      signal: options.signal ? AbortSignal.any([options.signal, timeout]) : timeout,
    });
  } catch (cause) {
    throw new UpstreamError(`Schedule request failed for ${regionId}`, { cause });
  }
  if (!res.ok) throw new UpstreamError(`Schedule source responded ${res.status} for ${regionId}`);
  let body: unknown;
  try {
    body = await res.json();
  } catch (cause) {
    throw new UpstreamError(`Schedule source returned invalid JSON for ${regionId}`, { cause });
  }
  return parseGpv(regionId, body, options.now ?? new Date());
}

export function parseGpv(regionId: string, body: unknown, now: Date): Map<string, GroupSchedule> {
  if (!isRecord(body) || !isRecord(body.fact) || !isRecord(body.fact.data)) {
    throw new UpstreamError(`Schedule for ${regionId} has no "fact.data"`);
  }
  const today = kyivTime(now).date;
  const tomorrow = addDays(today, 1);
  const updatedAt = typeof body.lastUpdated === 'string' ? body.lastUpdated : null;

  // date -> group -> slots
  const byDate = new Map<string, Map<string, Slot[]>>();
  for (const [dayKey, groups] of Object.entries(body.fact.data)) {
    const seconds = Number(dayKey);
    if (!Number.isFinite(seconds) || !isRecord(groups)) continue;
    // Keys are Kyiv midnights; take the date a few hours later to be safe around DST changes.
    const date = kyivTime(new Date((seconds + 3 * 3600) * 1000)).date;
    const perGroup = new Map<string, Slot[]>();
    for (const [key, hours] of Object.entries(groups)) {
      const m = GROUP_KEY.exec(key);
      if (!m?.[1] || !isRecord(hours)) continue;
      perGroup.set(m[1], hoursToSlots(hours));
    }
    byDate.set(date, perGroup);
  }

  const groupIds = new Set([...byDate.values()].flatMap((g) => [...g.keys()]));
  if (groupIds.size === 0) throw new UpstreamError(`Schedule for ${regionId} has no groups`);

  const day = (date: string, group: string): DaySchedule => {
    const slots = byDate.get(date)?.get(group);
    return slots ? { date, status: 'scheduled', slots: normalizeSlots(slots) } : { date, status: 'none', slots: [] };
  };

  return new Map(
    [...groupIds].map((group) => [
      group,
      { region: regionId, group, updatedAt, today: day(today, group), tomorrow: day(tomorrow, group) },
    ]),
  );
}

function hoursToSlots(hours: Record<string, unknown>): Slot[] {
  const slots: Slot[] = [];
  for (const [hourKey, value] of Object.entries(hours)) {
    const hour = Number(hourKey);
    const rule = typeof value === 'string' ? HALF[value] : undefined;
    if (!rule || !Number.isInteger(hour) || hour < 1 || hour > 24) continue;
    const start = (hour - 1) * 60;
    if (rule.part === 'all') slots.push({ start, end: start + 60, kind: rule.kind });
    if (rule.part === 'first') slots.push({ start, end: start + 30, kind: rule.kind });
    if (rule.part === 'second') slots.push({ start: start + 30, end: start + 60, kind: rule.kind });
  }
  return slots;
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}
