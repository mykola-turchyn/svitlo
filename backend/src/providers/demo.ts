import { normalizeSlots, type DaySchedule, type GroupSchedule, type Slot } from '../domain/schedule.ts';
import { addDays, kyivTime } from '../domain/time.ts';
import { CATALOG, findRegion, regionInfo } from './catalog.ts';
import { RegionUnavailableError, UnknownRegionError, type RegionInfo, type ScheduleProvider } from './provider.ts';

export const DEMO_GROUPS = ['1.1', '1.2', '2.1', '2.2', '3.1', '3.2', '4.1', '4.2', '5.1', '5.2', '6.1', '6.2'] as const;

/**
 * Deterministic fake schedules: same date + group always gives the same slots.
 * Used for local development, tests, UI previews and when Yasno is unreachable.
 */
export class DemoProvider implements ScheduleProvider {
  readonly name = 'demo';
  private readonly now: () => Date;

  constructor(options: { now?: () => Date } = {}) {
    this.now = options.now ?? (() => new Date());
  }

  regions(): RegionInfo[] {
    return CATALOG.map(regionInfo);
  }

  async fetchRegion(regionId: string): Promise<Map<string, GroupSchedule>> {
    const region = findRegion(regionId);
    if (!region) throw new UnknownRegionError(regionId);
    if (region.source.kind === 'none') throw new RegionUnavailableError(regionId);
    const today = kyivTime(this.now()).date;
    const tomorrow = addDays(today, 1);
    return new Map(
      DEMO_GROUPS.map((group, i) => [
        group,
        {
          region: regionId,
          group,
          updatedAt: `${today}T18:00:00+02:00`,
          today: demoDay(today, i),
          tomorrow: demoDay(tomorrow, i),
        },
      ]),
    );
  }
}

/** Two 4-hour outages 12 hours apart plus one possible hour, shifted by group and date. */
export function demoDay(date: string, groupIndex: number): DaySchedule {
  const dayNumber = Math.floor(Date.parse(`${date}T00:00:00Z`) / 86_400_000);
  const base = ((groupIndex * 2 + dayNumber * 3) % 8) * 60;
  const slots: Slot[] = [
    { start: base, end: base + 240, kind: 'off' },
    { start: base + 240, end: base + 300, kind: 'maybe' },
    { start: base + 720, end: base + 960, kind: 'off' },
  ];
  return { date, status: 'scheduled', slots: normalizeSlots(slots) };
}
