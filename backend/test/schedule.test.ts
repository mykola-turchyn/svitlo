import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { currentState, normalizeSlots, offMinutes, type DaySchedule } from '../src/domain/schedule.ts';
import { addDays, formatMinute, kyivTime } from '../src/domain/time.ts';

const day = (slots: DaySchedule['slots'], date = '2026-11-17'): DaySchedule => ({ date, status: 'scheduled', slots });

describe('normalizeSlots', () => {
  it('sorts, clamps and merges touching slots of the same kind', () => {
    assert.deepEqual(
      normalizeSlots([
        { start: 600, end: 720, kind: 'off' },
        { start: -30, end: 120, kind: 'off' },
        { start: 480, end: 600, kind: 'off' },
        { start: 1400, end: 1500, kind: 'off' },
      ]),
      [
        { start: 0, end: 120, kind: 'off' },
        { start: 480, end: 720, kind: 'off' },
        { start: 1400, end: 1440, kind: 'off' },
      ],
    );
  });

  it('drops empty slots and lets off win over maybe', () => {
    assert.deepEqual(
      normalizeSlots([
        { start: 100, end: 100, kind: 'off' },
        { start: 600, end: 900, kind: 'maybe' },
        { start: 700, end: 800, kind: 'off' },
      ]),
      [
        { start: 600, end: 700, kind: 'maybe' },
        { start: 700, end: 800, kind: 'off' },
        { start: 800, end: 900, kind: 'maybe' },
      ],
    );
  });
});

describe('currentState', () => {
  const schedule = {
    today: day([
      { start: 480, end: 720, kind: 'off' },
      { start: 720, end: 780, kind: 'maybe' },
      { start: 1080, end: 1320, kind: 'off' },
    ]),
    tomorrow: day([{ start: 240, end: 480, kind: 'off' }], '2026-11-18'),
  };

  it('reports power and the next outage', () => {
    assert.deepEqual(currentState(schedule, 14 * 60 + 20), { isOn: true, nextChangeAt: 1080 });
  });

  it('reports an outage and when power returns', () => {
    assert.deepEqual(currentState(schedule, 9 * 60), { isOn: false, nextChangeAt: 720 });
  });

  it('does not treat a possible outage as an outage', () => {
    assert.equal(currentState(schedule, 12 * 60 + 30).isOn, true);
  });

  it('looks into tomorrow after the last outage of today', () => {
    assert.deepEqual(currentState(schedule, 23 * 60), { isOn: true, nextChangeAt: 1440 + 240 });
  });

  it('merges an outage that runs across midnight', () => {
    const overnight = {
      today: day([{ start: 1320, end: 1440, kind: 'off' }]),
      tomorrow: day([{ start: 0, end: 120, kind: 'off' }], '2026-11-18'),
    };
    assert.deepEqual(currentState(overnight, 1400), { isOn: false, nextChangeAt: 1440 + 120 });
  });

  it('returns null when nothing is planned', () => {
    assert.deepEqual(currentState({ today: day([]), tomorrow: day([]) }, 600), { isOn: true, nextChangeAt: null });
  });
});

describe('time helpers', () => {
  it('uses Kyiv wall-clock time', () => {
    // 21:30 UTC in November is 23:30 in Kyiv (UTC+2).
    assert.deepEqual(kyivTime(new Date('2026-11-17T21:30:00Z')), { date: '2026-11-17', minute: 23 * 60 + 30 });
    assert.deepEqual(kyivTime(new Date('2026-11-17T22:30:00Z')), { date: '2026-11-18', minute: 30 });
  });

  it('adds days across months and formats minutes', () => {
    assert.equal(addDays('2026-11-30', 1), '2026-12-01');
    assert.equal(formatMinute(1080), '18:00');
    assert.equal(formatMinute(1440), '24:00');
  });

  it('sums outage minutes', () => {
    assert.equal(offMinutes(day([{ start: 0, end: 60, kind: 'off' }, { start: 60, end: 120, kind: 'maybe' }])), 60);
  });
});
