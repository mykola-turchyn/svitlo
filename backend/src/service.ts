import { TtlCache } from './cache.ts';
import { currentState, type CurrentState, type GroupSchedule } from './domain/schedule.ts';
import { kyivTime, type LocalTime } from './domain/time.ts';
import { RegionUnavailableError, UnknownRegionError, type RegionInfo, type ScheduleProvider } from './providers/provider.ts';

export class UnknownGroupError extends Error {
  readonly groups: string[];
  constructor(groups: string[]) {
    super(`Unknown group(s): ${groups.join(', ')}`);
    this.name = 'UnknownGroupError';
    this.groups = groups;
  }
}

export interface GroupWithState extends GroupSchedule {
  current: CurrentState;
}

export interface RegionSchedules {
  region: string;
  source: string;
  fetchedAt: string;
  stale: boolean;
  now: LocalTime;
  groups: GroupWithState[];
  /** Requested groups the region does not have (e.g. old group numbers after a renumbering). */
  missing: string[];
}

export class ScheduleService {
  private readonly provider: ScheduleProvider;
  private readonly cache: TtlCache<Map<string, GroupSchedule>>;
  private readonly now: () => Date;

  constructor(provider: ScheduleProvider, options: { ttlMs?: number; maxStaleMs?: number; now?: () => Date } = {}) {
    this.provider = provider;
    this.now = options.now ?? (() => new Date());
    this.cache = new TtlCache({
      ttlMs: options.ttlMs ?? 5 * 60_000,
      maxStaleMs: options.maxStaleMs ?? 6 * 60 * 60_000,
      now: () => this.now().getTime(),
    });
  }

  get source(): string {
    return this.provider.name;
  }

  regions(): RegionInfo[] {
    return this.provider.regions();
  }

  async groups(regionId: string): Promise<string[]> {
    const { value } = await this.load(regionId);
    return [...value.keys()].sort(compareGroups);
  }

  /** Schedules for some (or all, when `groups` is empty) groups of a region, with the current state. */
  async schedules(regionId: string, groups: string[] = []): Promise<RegionSchedules> {
    const { value, storedAt, stale } = await this.load(regionId);
    const wanted = groups.length ? groups : [...value.keys()].sort(compareGroups);
    const missing = wanted.filter((g) => !value.has(g));
    // One stale group must not hide the others; fail only when nothing matches.
    if (missing.length === wanted.length) throw new UnknownGroupError(missing);

    const now = kyivTime(this.now());
    return {
      region: regionId,
      source: this.provider.name,
      fetchedAt: new Date(storedAt).toISOString(),
      stale,
      now,
      missing,
      groups: wanted.filter((g) => value.has(g)).map((g) => {
        const schedule = value.get(g)!;
        // The provider's "today" can lag behind midnight; only trust it when the dates match.
        const minute = schedule.today.date === now.date ? now.minute : now.minute + 1440;
        return { ...schedule, current: currentState(schedule, minute) };
      }),
    };
  }

  private load(regionId: string) {
    const region = this.provider.regions().find((r) => r.id === regionId);
    if (!region) throw new UnknownRegionError(regionId);
    if (!region.available) throw new RegionUnavailableError(regionId);
    return this.cache.get(regionId, () => this.provider.fetchRegion(regionId));
  }
}

/** Sorts `2.1` before `10.1` (numeric, not lexicographic). */
export function compareGroups(a: string, b: string): number {
  const [a1 = 0, a2 = 0] = a.split('.').map(Number);
  const [b1 = 0, b2 = 0] = b.split('.').map(Number);
  return a1 - b1 || a2 - b2;
}
