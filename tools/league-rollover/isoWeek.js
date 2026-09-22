'use strict';

// Mirrors lib/core/utils/league_scoring.dart's isoWeekId/currentWeekStartUtc
// EXACTLY — there's no shared library between Dart and Node, so any change
// here must be made identically on both sides. Ported verbatim from
// Capitle's own tools/league-rollover/isoWeek.js (generic ISO week math,
// nothing Capitle-specific in it).

/** @param {Date} utcDate a Date already in UTC (use Date.UTC(...) to build one) */
function isoWeekId(utcDate) {
  const date = new Date(Date.UTC(utcDate.getUTCFullYear(), utcDate.getUTCMonth(), utcDate.getUTCDate()));
  const isoWeekday = date.getUTCDay() === 0 ? 7 : date.getUTCDay(); // Mon=1..Sun=7
  const thursday = new Date(date);
  thursday.setUTCDate(date.getUTCDate() + (4 - isoWeekday));

  const jan4 = new Date(Date.UTC(thursday.getUTCFullYear(), 0, 4));
  const jan4Weekday = jan4.getUTCDay() === 0 ? 7 : jan4.getUTCDay();
  const firstWeekMonday = new Date(jan4);
  firstWeekMonday.setUTCDate(jan4.getUTCDate() - (jan4Weekday - 1));

  const weekNumber = Math.floor((thursday - firstWeekMonday) / (7 * 86400000)) + 1;
  return `${thursday.getUTCFullYear()}-W${String(weekNumber).padStart(2, '0')}`;
}

/** Monday 00:00:00 UTC of the ISO week containing [now]. */
function currentWeekStartUtc(now) {
  const n = now || new Date();
  const today = new Date(Date.UTC(n.getUTCFullYear(), n.getUTCMonth(), n.getUTCDate()));
  const isoWeekday = today.getUTCDay() === 0 ? 7 : today.getUTCDay();
  today.setUTCDate(today.getUTCDate() - (isoWeekday - 1));
  return today;
}

function addDays(date, days) {
  const d = new Date(date);
  d.setUTCDate(d.getUTCDate() + days);
  return d;
}

module.exports = { isoWeekId, currentWeekStartUtc, addDays };
