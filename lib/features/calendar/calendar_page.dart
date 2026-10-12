import 'dart:async';

import 'package:flutter/material.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_switcher.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    required this.profileController,
    required this.entryRepository,
    this.initialMonth,
    super.key,
  });

  final ProfileController profileController;
  final EntryRepository entryRepository;
  final DateTime? initialMonth;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  late DateTime _selectedDay;
  Map<String, int> _counts = const <String, int>{};
  List<JournalEntry> _entries = const <JournalEntry>[];
  String? _profileId;
  int _monthGeneration = 0;
  int _dayGeneration = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth ?? DateTime.now();
    _month = DateTime(initial.year, initial.month);
    _selectedDay = DateTime(initial.year, initial.month, initial.day);
    widget.profileController.addListener(_syncProfile);
    _syncProfile();
  }

  @override
  void dispose() {
    widget.profileController.removeListener(_syncProfile);
    super.dispose();
  }

  void _syncProfile() {
    final profileId = widget.profileController.active?.id;
    if (profileId == null || profileId == _profileId) return;
    _profileId = profileId;
    unawaited(
      _loadMonthAndDay(profileId, ++_monthGeneration, ++_dayGeneration),
    );
  }

  Future<void> _loadMonthAndDay(
    String profileId,
    int monthGeneration,
    int dayGeneration,
  ) async {
    final start = _month;
    final end = DateTime(_month.year, _month.month + 1, 0);
    final countsFuture = widget.entryRepository.countByDay(
      profileId,
      start,
      end,
    );
    final entriesFuture = widget.entryRepository.listDay(
      profileId,
      _selectedDay,
    );
    final counts = await countsFuture;
    if (!mounted ||
        monthGeneration != _monthGeneration ||
        profileId != widget.profileController.active?.id) {
      return;
    }
    setState(() => _counts = counts);

    final entries = await entriesFuture;
    if (!mounted ||
        dayGeneration != _dayGeneration ||
        profileId != widget.profileController.active?.id) {
      return;
    }
    setState(() => _entries = entries);
  }

  Future<void> _loadSelectedDay(String profileId, int generation) async {
    final entries = await widget.entryRepository.listDay(
      profileId,
      _selectedDay,
    );
    if (!mounted ||
        generation != _dayGeneration ||
        profileId != widget.profileController.active?.id) {
      return;
    }
    setState(() => _entries = entries);
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDay = DateTime(_month.year, _month.month, 1);
      _counts = const <String, int>{};
      _entries = const <JournalEntry>[];
    });
    final profileId = widget.profileController.active?.id;
    if (profileId != null) {
      unawaited(
        _loadMonthAndDay(profileId, ++_monthGeneration, ++_dayGeneration),
      );
    }
  }

  void _select(DateTime day) {
    setState(() {
      _selectedDay = day;
      _entries = const <JournalEntry>[];
    });
    final profileId = widget.profileController.active?.id;
    if (profileId != null) {
      unawaited(_loadSelectedDay(profileId, ++_dayGeneration));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ProfileSwitcher(controller: widget.profileController),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                IconButton(
                  key: const Key('calendar-previous-month'),
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${_month.year}年${_month.month}月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                IconButton(
                  key: const Key('calendar-next-month'),
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const _WeekHeader(),
            _MonthGrid(
              month: _month,
              selectedDay: _selectedDay,
              counts: _counts,
              onSelect: _select,
            ),
            const SizedBox(height: 12),
            Text(
              '${_selectedDay.month}月${_selectedDay.day}日',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _entries.isEmpty
                  ? const Center(child: Text('暂无记录'))
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        return Card(
                          key: Key('calendar-entry-${entry.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(entry.text),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader();
  @override
  Widget build(BuildContext context) => const Row(
    children: <Widget>[
      _Weekday('日'),
      _Weekday('一'),
      _Weekday('二'),
      _Weekday('三'),
      _Weekday('四'),
      _Weekday('五'),
      _Weekday('六'),
    ],
  );
}

class _Weekday extends StatelessWidget {
  const _Weekday(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Expanded(child: Center(child: Text(label)));
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selectedDay,
    required this.counts,
    required this.onSelect,
  });
  final DateTime month;
  final DateTime selectedDay;
  final Map<String, int> counts;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final leading = DateTime(month.year, month.month, 1).weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
    ];
    for (var day = 1; day <= days; day++) {
      final date = DateTime(month.year, month.month, day);
      final key = _dateKey(date);
      final count = counts[key];
      final selected = _sameDay(date, selectedDay);
      cells.add(
        InkWell(
          key: Key('calendar-day-$key'),
          onTap: () => onSelect(date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: selected
                ? BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text('$day'),
                if (count != null)
                  Row(
                    key: Key('calendar-count-$key'),
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.circle, size: 6),
                      const SizedBox(width: 3),
                      Text('$count'),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: 48,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cells.length,
      itemBuilder: (context, index) => cells[index],
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
