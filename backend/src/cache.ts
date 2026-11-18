interface Entry<T> {
  value: T;
  storedAt: number;
}

export interface CacheResult<T> {
  value: T;
  /** When the value was loaded from upstream. */
  storedAt: number;
  /** True when upstream failed and an older value was served instead. */
  stale: boolean;
}

/**
 * A small TTL cache for upstream data:
 * - concurrent requests for the same key share one upstream call;
 * - if upstream fails, the last good value is served (marked `stale`) for up to `maxStaleMs`.
 */
export class TtlCache<T> {
  private readonly entries = new Map<string, Entry<T>>();
  private readonly inflight = new Map<string, Promise<Entry<T>>>();
  private readonly ttlMs: number;
  private readonly maxStaleMs: number;
  private readonly now: () => number;

  constructor(options: { ttlMs: number; maxStaleMs: number; now?: () => number }) {
    this.ttlMs = options.ttlMs;
    this.maxStaleMs = options.maxStaleMs;
    this.now = options.now ?? Date.now;
  }

  async get(key: string, load: () => Promise<T>): Promise<CacheResult<T>> {
    const cached = this.entries.get(key);
    const age = cached ? this.now() - cached.storedAt : Infinity;
    if (cached && age < this.ttlMs) return { ...cached, stale: false };

    try {
      const fresh = await this.load(key, load);
      return { ...fresh, stale: false };
    } catch (error) {
      if (cached && age < this.maxStaleMs) return { ...cached, stale: true };
      throw error;
    }
  }

  private load(key: string, load: () => Promise<T>): Promise<Entry<T>> {
    const pending = this.inflight.get(key);
    if (pending) return pending;
    const promise = load()
      .then((value) => {
        const entry = { value, storedAt: this.now() };
        this.entries.set(key, entry);
        return entry;
      })
      .finally(() => this.inflight.delete(key));
    this.inflight.set(key, promise);
    return promise;
  }
}
