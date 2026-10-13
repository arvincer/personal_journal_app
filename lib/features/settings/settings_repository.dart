import 'dart:math';

import 'package:sqflite/sqflite.dart';

abstract interface class SettingsRepository {
  Future<bool> readIncludeOriginalVideos();
  Future<void> writeIncludeOriginalVideos(bool value);
  Future<DateTime?> readLastSideloadRefreshDate();
  Future<void> writeLastSideloadRefreshDate(DateTime value);
}

final class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._database);

  static const exportIncludeOriginalVideosKey =
      'export_include_original_videos';
  static const lastSideloadRefreshDateKey = 'last_sideload_refresh_date';

  final Database _database;

  @override
  Future<bool> readIncludeOriginalVideos() async =>
      await _read(exportIncludeOriginalVideosKey) == 'true';

  @override
  Future<void> writeIncludeOriginalVideos(bool value) =>
      _write(exportIncludeOriginalVideosKey, value.toString());

  @override
  Future<DateTime?> readLastSideloadRefreshDate() async {
    final value = await _read(lastSideloadRefreshDateKey);
    if (value == null) return null;
    final parsed = DateTime.parse(value);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  @override
  Future<void> writeLastSideloadRefreshDate(DateTime value) => _write(
    lastSideloadRefreshDateKey,
    _dateOnly(value).toIso8601String().substring(0, 10),
  );

  Future<String?> _read(String key) async {
    final rows = await _database.query(
      'settings',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  Future<void> _write(String key, String value) async {
    await _database.insert('settings', <String, Object?>{
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

int estimatedSideloadDaysRemaining({
  required DateTime refreshDate,
  required DateTime today,
}) {
  final elapsed = _dateOnly(today).difference(_dateOnly(refreshDate)).inDays;
  return max(0, 7 - max(0, elapsed));
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
