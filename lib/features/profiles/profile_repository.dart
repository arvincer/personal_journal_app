import 'dart:async';
import 'dart:collection';

import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

typedef ProfileIdProvider = String Function();
typedef ProfileNowProvider = DateTime Function();

abstract interface class ProfileRepository {
  Future<Profile> ensureDefaultProfile();
  Future<List<Profile>> listActive();
  Future<Profile> create({required String name});
  Future<void> rename({required String id, required String name});
  Future<void> archive(String id);
  Future<String?> readActiveProfileId();
  Future<void> writeActiveProfileId(String id);
}

final class SqliteProfileRepository implements ProfileRepository {
  SqliteProfileRepository(
    this._database, {
    ProfileIdProvider? idProvider,
    ProfileNowProvider? nowProvider,
  }) : _idProvider = idProvider ?? const Uuid().v4,
       _nowProvider = nowProvider ?? DateTime.now;

  static const _activeProfileKey = 'active_profile_id';
  static final HashMap<Database, Future<void>> _defaultCreationTails =
      HashMap<Database, Future<void>>.identity();

  final Database _database;
  final ProfileIdProvider _idProvider;
  final ProfileNowProvider _nowProvider;

  @override
  Future<Profile> ensureDefaultProfile() {
    return _serializeDefaultCreation(() async {
      return _database.transaction((transaction) async {
        final activeRows = await transaction.query(
          'profiles',
          where: 'is_archived = ?',
          whereArgs: <Object?>[0],
          orderBy: 'is_default DESC, created_at ASC, id ASC',
        );
        if (activeRows.isNotEmpty) {
          return Profile.fromMap(activeRows.first);
        }

        final profileCount = Sqflite.firstIntValue(
          await transaction.rawQuery('SELECT COUNT(*) FROM profiles'),
        );
        if (profileCount != 0) {
          throw StateError('No active profile exists.');
        }

        final now = _nowProvider();
        final profile = Profile(
          id: _idProvider(),
          name: '我的日志',
          avatarPath: null,
          createdAt: now,
          updatedAt: now,
          isDefault: true,
          isArchived: false,
        );
        await transaction.insert('profiles', profile.toMap());
        return profile;
      });
    });
  }

  @override
  Future<List<Profile>> listActive() async {
    final rows = await _database.query(
      'profiles',
      where: 'is_archived = ?',
      whereArgs: <Object?>[0],
      orderBy: 'is_default DESC, created_at ASC, id ASC',
    );
    return rows.map(Profile.fromMap).toList(growable: false);
  }

  @override
  Future<Profile> create({required String name}) async {
    final normalizedName = _normalizeName(name);
    final now = _nowProvider();
    final profile = Profile(
      id: _idProvider(),
      name: normalizedName,
      avatarPath: null,
      createdAt: now,
      updatedAt: now,
      isDefault: false,
      isArchived: false,
    );
    await _database.insert('profiles', profile.toMap());
    return profile;
  }

  @override
  Future<void> rename({required String id, required String name}) async {
    final normalizedName = _normalizeName(name);
    final updatedRows = await _database.update(
      'profiles',
      <String, Object?>{
        'name': normalizedName,
        'updated_at': _nowProvider().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (updatedRows == 0) {
      throw StateError('Cannot rename unknown profile "$id".');
    }
  }

  @override
  Future<void> archive(String id) async {
    final updatedRows = await _database.update(
      'profiles',
      <String, Object?>{
        'is_archived': 1,
        'updated_at': _nowProvider().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (updatedRows == 0) {
      throw StateError('Cannot archive unknown profile "$id".');
    }
  }

  @override
  Future<String?> readActiveProfileId() async {
    final rows = await _database.query(
      'settings',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[_activeProfileKey],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  @override
  Future<void> writeActiveProfileId(String id) async {
    await _database.insert('settings', <String, Object?>{
      'key': _activeProfileKey,
      'value': id,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<T> _serializeDefaultCreation<T>(Future<T> Function() operation) async {
    final previous = _defaultCreationTails[_database] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = previous.then<void>(
      (_) => release.future,
      onError: (_) => release.future,
    );
    _defaultCreationTails[_database] = tail;

    try {
      try {
        await previous;
      } catch (_) {
        // A prior caller's failure must not permanently poison the lock.
      }
      return await operation();
    } finally {
      release.complete();
      if (identical(_defaultCreationTails[_database], tail)) {
        _defaultCreationTails.remove(_database);
      }
    }
  }

  String _normalizeName(String name) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Profile name cannot be blank.');
    }
    return normalizedName;
  }
}
