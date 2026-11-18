import type { GroupSchedule } from '../domain/schedule.ts';

export interface RegionInfo {
  /** Our stable slug, used in URLs and stored by the app (e.g. `kyiv`). */
  id: string;
  /** Ukrainian display name. */
  name: string;
  /** Distribution system operator shown to the user. */
  operator: string;
  /** False when no open data source exists yet; the app lists the region but cannot follow it. */
  available: boolean;
}

/**
 * A source of outage schedules. One provider can serve several regions.
 * `fetchRegion` returns every group of the region in one go, because that is
 * how upstream APIs publish them and it keeps the cache simple.
 */
export interface ScheduleProvider {
  readonly name: string;
  regions(): RegionInfo[];
  fetchRegion(regionId: string, signal?: AbortSignal): Promise<Map<string, GroupSchedule>>;
}

export class UnknownRegionError extends Error {
  readonly regionId: string;
  constructor(regionId: string) {
    super(`Unknown region: ${regionId}`);
    this.name = 'UnknownRegionError';
    this.regionId = regionId;
  }
}

export class RegionUnavailableError extends Error {
  readonly regionId: string;
  constructor(regionId: string) {
    super(`No schedule source for region: ${regionId}`);
    this.name = 'RegionUnavailableError';
    this.regionId = regionId;
  }
}

export class UpstreamError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = 'UpstreamError';
  }
}
