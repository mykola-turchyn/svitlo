import type { GroupSchedule } from '../domain/schedule.ts';
import { CATALOG, findRegion, regionInfo, type CatalogRegion } from './catalog.ts';
import { fetchGpv } from './gpv.ts';
import { RegionUnavailableError, UnknownRegionError, type RegionInfo, type ScheduleProvider } from './provider.ts';
import { fetchYasno } from './yasno.ts';

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

/** Real data: routes each region to its source from the catalog. */
export class LiveProvider implements ScheduleProvider {
  readonly name = 'live';
  private readonly fetchFn: FetchFn | undefined;
  private readonly catalog: readonly CatalogRegion[];
  private readonly now: () => Date;

  constructor(options: { fetch?: FetchFn; catalog?: readonly CatalogRegion[]; now?: () => Date } = {}) {
    this.fetchFn = options.fetch;
    this.catalog = options.catalog ?? CATALOG;
    this.now = options.now ?? (() => new Date());
  }

  regions(): RegionInfo[] {
    return this.catalog.map(regionInfo);
  }

  async fetchRegion(regionId: string, signal?: AbortSignal): Promise<Map<string, GroupSchedule>> {
    const region = this.catalog === CATALOG ? findRegion(regionId) : this.catalog.find((r) => r.id === regionId);
    if (!region) throw new UnknownRegionError(regionId);
    const options = { fetch: this.fetchFn, signal, now: this.now() };
    switch (region.source.kind) {
      case 'yasno':
        return fetchYasno(region.source, regionId, options);
      case 'gpv':
        return fetchGpv(region.source.url, regionId, options);
      case 'none':
        throw new RegionUnavailableError(regionId);
    }
  }
}
