/// Pure week-boundary math for the league system. No side effects, no
/// Firestore/Riverpod dependencies. Ported from Capitle's own
/// league_scoring.dart — Mixoloco has no per-game scoring formula to
/// port alongside it (there's one game mode here, and its score is
/// whatever the physics game itself already produces), so only the ISO
/// week helpers carry over.
library;

/// ISO-8601 week identifier, e.g. "2026-W33". Must stay in lockstep with
/// the identical formula reimplemented in tools/league-rollover/isoWeek.js
/// — no shared library between Dart and Node, so both copies are annotated
/// with this same warning.
String isoWeekId(DateTime utc) {
  final date = DateTime.utc(utc.year, utc.month, utc.day);
  // ISO week date: Thursday of the current week determines the week-year.
  final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
  // Jan 4 always falls in week 1 of its ISO year — the Monday of Jan 4's
  // own week is where week numbering starts.
  final jan4 = DateTime.utc(thursday.year, 1, 4);
  final firstWeekMonday = jan4.subtract(Duration(days: (jan4.weekday + 6) % 7));
  final weekNumber = (thursday.difference(firstWeekMonday).inDays / 7).floor() + 1;
  return '${thursday.year}-W${weekNumber.toString().padLeft(2, '0')}';
}

/// UTC instant the current ISO week began (Monday 00:00:00 UTC).
DateTime currentWeekStartUtc([DateTime? now]) {
  final n = (now ?? DateTime.now()).toUtc();
  final today = DateTime.utc(n.year, n.month, n.day);
  return today.subtract(Duration(days: (today.weekday + 6) % 7));
}

DateTime nextWeekStartUtc([DateTime? now]) => currentWeekStartUtc(now).add(const Duration(days: 7));

Duration timeUntilNextRollover([DateTime? now]) => nextWeekStartUtc(now).difference((now ?? DateTime.now()).toUtc());

/// The daily new-joiner room assignment (tools/league-rollover/
/// assignNewJoiners.js) runs once a day at this UTC hour — separate from
/// the weekly Monday-00:00 rollover, so a new signup waits at most ~24h
/// to be placed in a room with other same-day joiners, instead of up to
/// 6 days for the next Monday. Must stay in lockstep with the identical
/// hour hardcoded in that script's own cron schedule (see
/// .github/workflows/league-daily-join.yml).
const _dailyJoinHourUtc = 12;

DateTime nextDailyJoinUtc([DateTime? now]) {
  final n = (now ?? DateTime.now()).toUtc();
  final todayCutoff = DateTime.utc(n.year, n.month, n.day, _dailyJoinHourUtc);
  return n.isBefore(todayCutoff) ? todayCutoff : todayCutoff.add(const Duration(days: 1));
}

Duration timeUntilNextDailyJoin([DateTime? now]) => nextDailyJoinUtc(now).difference((now ?? DateTime.now()).toUtc());
