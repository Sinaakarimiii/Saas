import assert from 'node:assert/strict';
import { test } from 'node:test';
import { tehranDayBounds, tehranISODate } from '../src/lib/tehran-time.ts';
import { shiftSegmentForDay } from '../src/lib/shift-day.ts';

test('Tehran date changes at Tehran midnight, independent of host timezone', () => {
  assert.equal(tehranISODate(new Date('2026-09-20T20:29:59.999Z')), '2026-09-20');
  assert.equal(tehranISODate(new Date('2026-09-20T20:30:00.000Z')), '2026-09-21');
  assert.deepEqual(tehranDayBounds('2026-09-21'), {
    start: '2026-09-20T20:30:00.000Z',
    end: '2026-09-21T20:30:00.000Z',
  });
});

test('adjacent days have no gap or overlap', () => {
  assert.equal(tehranDayBounds('2026-09-21').end, tehranDayBounds('2026-09-22').start);
});

test('night shift spans both Tehran calendar days, including a month boundary', () => {
  const shift = { workDate: '2026-09-30', startTime: '22:00', endTime: '06:00' };
  assert.deepEqual(shiftSegmentForDay(shift, '2026-09-30'), {
    start: 1320, end: 1440, continuesFromPreviousDay: false,
  });
  assert.deepEqual(shiftSegmentForDay(shift, '2026-10-01'), {
    start: 0, end: 360, continuesFromPreviousDay: true,
  });
  assert.equal(shiftSegmentForDay(shift, '2026-10-02'), null);
});

test('ordinary shift stays on its start date', () => {
  const shift = { workDate: '2026-09-30', startTime: '09:00', endTime: '17:00' };
  assert.deepEqual(shiftSegmentForDay(shift, '2026-09-30'), {
    start: 540, end: 1020, continuesFromPreviousDay: false,
  });
  assert.equal(shiftSegmentForDay(shift, '2026-10-01'), null);
});
