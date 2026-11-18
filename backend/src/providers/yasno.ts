import { normalizeSlots, type DaySchedule, type DayStatus, type GroupSchedule, type Slot } from '../domain/schedule.ts';
import { addDays, kyivTime } from '../domain/time.ts';
import { UpstreamError } from './provider.ts';

/**
 * Yasno (DTEK) public blackout service.
 * Planned outages: GET {base}/regions/{regionId}/dsos/{dsoId}/planned-outages
 * Response: { "1.1": { today: Day, tomorrow: Day, updatedOn }, "1.2": … }
 * Day: { slots: [{ start, end, type }], date, status }, start/end in minutes from midnight.
 */
const BASE = 'https://app.yasno.ua/api/blackout-service/public/shutdowns';

const GROUP_KEY = /^\d{1,2}\.\d{1,2}$/;

const STATUS: Record<string, DayStatus> = {
  ScheduleApplies: 'scheduled',
  WaitingForSchedule: 'waiting',
  EmergencyShutdowns: 'emergency',
};

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

export async function fetchYasno(
  source: { regionId: number; dsoId: number },
  regionId: string,
  options: { fetch?: FetchFn; timeoutMs?: number; signal?: AbortSignal; now?: Date } = {},
): Promise<Map<string, GroupSchedule>> {
  const fetchFn = options.fetch ?? ((input, init) => fetch(input, init));
  const url = `${BASE}/regions/${source.regionId}/dsos/${source.dsoId}/planned-outages`;
  const timeout = AbortSignal.timeout(options.timeoutMs ?? 8000);
  let res: Response;
  try {
    res = await fetchFn(url, {
      headers: { accept: 'application/json', 'user-agent': 'svitlo-backend/0.1' },
      signal: options.signal ? AbortSignal.any([options.signal, timeout]) : timeout,
    });
  } catch (cause) {
    throw new UpstreamError(`Yasno request failed for ${regionId}`, { cause });
  }
  if (!res.ok) throw new UpstreamError(`Yasno responded ${res.status} for ${regionId}`);

  let body: unknown;
  try {
    body = await res.json();
  } catch (cause) {
    throw new UpstreamError(`Yasno returned invalid JSON for ${regionId}`, { cause });
  }
  return parsePlannedOutages(regionId, body, options.now ?? new Date());
}

/** Turns a Yasno planned-outages payload into our model. Unknown fields are ignored. */
export function parsePlannedOutages(regionId: string, body: unknown, now: Date): Map<string, GroupSchedule> {
  if (!isRecord(body)) throw new UpstreamError('Yasno payload is not an object');
  const today = kyivTime(now).date;
  const result = new Map<string, GroupSchedule>();

  for (const [group, value] of Object.entries(body)) {
    if (!GROUP_KEY.test(group) || !isRecord(value)) continue;
    result.set(group, {
      region: regionId,
      group,
      updatedAt: typeof value.updatedOn === 'string' ? value.updatedOn : null,
      today: parseDay(value.today, today),
      tomorrow: parseDay(value.tomorrow, addDays(today, 1)),
    });
  }
  if (result.size === 0) throw new UpstreamError('Yasno payload has no groups');
  return result;
}

function parseDay(raw: unknown, fallbackDate: string): DaySchedule {
  if (!isRecord(raw)) return { date: fallbackDate, status: 'none', slots: [] };
  const date = typeof raw.date === 'string' && /^\d{4}-\d{2}-\d{2}/.test(raw.date) ? raw.date.slice(0, 10) : fallbackDate;
  const status = (typeof raw.status === 'string' && STATUS[raw.status]) || 'scheduled';
  const slots: Slot[] = [];
  for (const s of Array.isArray(raw.slots) ? raw.slots : []) {
    if (!isRecord(s) || typeof s.start !== 'number' || typeof s.end !== 'number') continue;
    if (s.type === 'NotPlanned') continue;
    slots.push({ start: s.start, end: s.end, kind: s.type === 'Definite' ? 'off' : 'maybe' });
  }
  return { date, status, slots: normalizeSlots(slots) };
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}
