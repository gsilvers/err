import 'package:flutter/material.dart';

import 'err_theme.dart';
import 'trip_repository.dart';
import 'trip_summary.dart';
import 'units.dart';

/// Browse totals and history for past activities. Reads everything from the
/// saved files via [TripRepository]; nothing here writes except deletes.
class StatsScreen extends StatefulWidget {
  const StatsScreen({
    super.key,
    required this.theme,
    required this.useImperial,
  });

  final ErrTheme theme;
  final bool useImperial;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  TripRepository? _repo;
  late Future<List<TripSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<TripSummary>> _load() async {
    final repo = _repo ??= await TripRepository.open();
    return repo.loadAll();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _confirmDelete(TripSummary trip) async {
    final t = widget.theme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.screenBackground,
        title: Text('Delete activity?',
            style: TextStyle(color: t.statValue)),
        content: Text(
          'This removes the GPX and CSV files for '
          '${_fmtDate(trip.date)} from your device. This cannot be undone.',
          style: TextStyle(color: t.statLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: t.statLabel)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: t.messageError)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _repo?.delete(trip);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Activity deleted')),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return Scaffold(
      backgroundColor: t.screenBackground,
      appBar: AppBar(
        backgroundColor: t.appBarBackground,
        iconTheme: IconThemeData(color: t.appBarTitle),
        title: Text('Statistics', style: TextStyle(color: t.appBarTitle)),
      ),
      body: FutureBuilder<List<TripSummary>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(color: t.startActive),
            );
          }
          final trips = snap.data ?? const [];
          if (trips.isEmpty) return _empty(t);
          return _content(t, TripStats(trips));
        },
      ),
    );
  }

  Widget _empty(ErrTheme t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insights, size: 48, color: t.statIcon),
              const SizedBox(height: 16),
              Text(
                'No activities yet',
                style: TextStyle(
                    color: t.statValue,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Press Start to record your first one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.statLabel),
              ),
            ],
          ),
        ),
      );

  Widget _content(ErrTheme t, TripStats stats) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _SummaryCard(
          theme: t,
          imperial: widget.useImperial,
          title: 'This Month',
          bucket: stats.thisMonth,
        ),
        const SizedBox(height: 12),
        _SummaryCard(
          theme: t,
          imperial: widget.useImperial,
          title: 'This Year',
          bucket: stats.thisYear,
        ),
        const SizedBox(height: 24),
        _sectionHeader(t, 'By Year'),
        for (final entry in stats.byYear)
          _YearRow(
            theme: t,
            imperial: widget.useImperial,
            year: entry.key,
            bucket: entry.value,
          ),
        const SizedBox(height: 24),
        _sectionHeader(t, 'History'),
        for (final trip in stats.trips)
          _HistoryRow(
            theme: t,
            imperial: widget.useImperial,
            trip: trip,
            date: _fmtDate(trip.date),
            onLongPress: () => _confirmDelete(trip),
          ),
      ],
    );
  }

  Widget _sectionHeader(ErrTheme t, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          text,
          style: TextStyle(
            color: t.statLabel,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDate(DateTime d) {
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '${_months[d.month - 1]} ${d.day}, ${d.year}  $h:$m';
}

// ─── Summary card (This Month / This Year) ───────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.theme,
    required this.imperial,
    required this.title,
    required this.bucket,
  });

  final ErrTheme theme;
  final bool imperial;
  final String title;
  final StatsBucket bucket;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final activities =
        '${bucket.tripCount} ${bucket.tripCount == 1 ? 'activity' : 'activities'}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.appBarBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(
                      color: t.statValue,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Text(activities,
                  style: TextStyle(color: t.statLabel, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatDistance(bucket.distanceMeters, imperial: imperial),
            style: TextStyle(
                color: t.statDistance,
                fontSize: 30,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniMetric(Icons.trending_up, t.statElevation,
                  formatElevation(bucket.elevationGainMeters, imperial: imperial)),
              const SizedBox(width: 24),
              _miniMetric(Icons.timer_outlined, t.statTime,
                  formatDuration(bucket.duration)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniMetric(IconData icon, Color color, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(color: theme.statValue, fontSize: 15)),
        ],
      );
}

// ─── Per-year row ────────────────────────────────────────────────────────────

class _YearRow extends StatelessWidget {
  const _YearRow({
    required this.theme,
    required this.imperial,
    required this.year,
    required this.bucket,
  });

  final ErrTheme theme;
  final bool imperial;
  final int year;
  final StatsBucket bucket;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text('$year',
                style: TextStyle(
                    color: t.statValue, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(
              formatDistance(bucket.distanceMeters, imperial: imperial),
              style: TextStyle(color: t.statDistance, fontSize: 15),
            ),
          ),
          Text(
            formatElevation(bucket.elevationGainMeters, imperial: imperial),
            style: TextStyle(color: t.statElevation, fontSize: 13),
          ),
          const SizedBox(width: 16),
          Text('${bucket.tripCount}×',
              style: TextStyle(color: t.statLabel, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── History row ─────────────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.theme,
    required this.imperial,
    required this.trip,
    required this.date,
    required this.onLongPress,
  });

  final ErrTheme theme;
  final bool imperial;
  final TripSummary trip;
  final String date;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return InkWell(
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.straighten, size: 18, color: t.statIcon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date,
                      style: TextStyle(color: t.statValue, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '+${formatElevation(trip.elevationGainMeters, imperial: imperial)}'
                    '  ·  ${formatDuration(trip.duration)}',
                    style: TextStyle(color: t.statLabel, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              formatDistance(trip.distanceMeters, imperial: imperial),
              style: TextStyle(
                  color: t.statDistance,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
