/**
 * Domain model for outage schedules.
 *
 * Every provider (Yasno, demo, future oblenergo scrapers) is normalised into
 * these shapes, so the API and the iOS app only ever see one format.
 * Times are minutes from local midnight (Europe/Kyiv), 0–1440.
 */

export const MINUTES_PER_DAY = 1440;

/** `off` — confirmed outage, `maybe` — possible outage (shown hatched in the UI). */
export type SlotKind = 'off' | 'maybe';

export interface Slot {
  start: number;
  end: number;
  kind: SlotKind;
}

/**
 * - `scheduled` — the provider published a schedule for this day
 * - `waiting`   — the provider has not published it yet (usually tomorrow before ~20:00)
 * - `emergency` — emergency shutdowns, schedules do not apply
 * - `none`      — no data for this day
 */
export type DayStatus = 'scheduled' | 'waiting' | 'emergency' | 'none';

export interface DaySchedule {
  /** Local date, `YYYY-MM-DD`. */
  date: string;
  status: DayStatus;
  slots: Slot[];
}

export interface GroupSchedule {
  region: string;
  group: string;
  /** When the provider last changed the schedule (ISO 8601), if known. */
  updatedAt: string | null;
  today: DaySchedule;
  tomorrow: DaySchedule;
}

export interface CurrentState {
  isOn: boolean;
  /** Minutes from today's midnight when the state next changes (may be > 1440 if it is tomorrow). */
  nextChangeAt: number | null;
}

const clamp = (n: number) => Math.min(MINUTES_PER_DAY, Math.max(0, Math.round(n)));

/**
 * Sorts slots, clamps them to the day, drops empty ones and merges slots of the
 * same kind that touch or overlap. Where `off` and `maybe` overlap, `off` wins.
 */
export function normalizeSlots(input: readonly Slot[]): Slot[] {
  const cleaned = input
    .map((s) => ({ start: clamp(s.start), end: clamp(s.end), kind: s.kind }))
    .filter((s) => s.end > s.start);

  const off = mergeSameKind(cleaned.filter((s) => s.kind === 'off'));
  const maybe = mergeSameKind(cleaned.filter((s) => s.kind === 'maybe'))
    .flatMap((m) => subtract(m, off));

  return [...off, ...maybe].sort((a, b) => a.start - b.start);
}

function mergeSameKind(slots: Slot[]): Slot[] {
  const sorted = [...slots].sort((a, b) => a.start - b.start);
  const out: Slot[] = [];
  for (const s of sorted) {
    const last = out.at(-1);
    if (last && s.start <= last.end) last.end = Math.max(last.end, s.end);
    else out.push({ ...s });
  }
  return out;
}

/** Removes the parts of `slot` covered by any of `cover`. */
function subtract(slot: Slot, cover: readonly Slot[]): Slot[] {
  let pieces: Slot[] = [slot];
  for (const c of cover) {
    pieces = pieces.flatMap((p) => {
      if (c.end <= p.start || c.start >= p.end) return [p];
      const parts: Slot[] = [];
      if (c.start > p.start) parts.push({ ...p, end: c.start });
      if (c.end < p.end) parts.push({ ...p, start: c.end });
      return parts;
    });
  }
  return pieces;
}

/**
 * Is there power right now, and when does that change?
 * Only `off` slots count as "no power"; `maybe` is shown but does not flip the state.
 */
export function currentState(schedule: Pick<GroupSchedule, 'today' | 'tomorrow'>, minuteOfDay: number): CurrentState {
  const offToday = schedule.today.slots.filter((s) => s.kind === 'off');
  const offTomorrow = schedule.tomorrow.slots
    .filter((s) => s.kind === 'off')
    .map((s) => ({ ...s, start: s.start + MINUTES_PER_DAY, end: s.end + MINUTES_PER_DAY }));
  const all = mergeSameKind([...offToday, ...offTomorrow]);

  const active = all.find((s) => minuteOfDay >= s.start && minuteOfDay < s.end);
  if (active) return { isOn: false, nextChangeAt: active.end };

  const next = all.find((s) => s.start > minuteOfDay);
  return { isOn: true, nextChangeAt: next ? next.start : null };
}

/** Total minutes without power in a day (`off` slots only). */
export function offMinutes(day: DaySchedule): number {
  return day.slots.filter((s) => s.kind === 'off').reduce((sum, s) => sum + (s.end - s.start), 0);
}
