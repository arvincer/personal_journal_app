import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('AppDatabase', () {
    late Database database;

    setUp(() async {
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
    });

    tearDown(() => database.close());

    test('creates all application tables', () async {
      final rows = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = rows.map((row) => row['name']).toSet();

      expect(
        tableNames,
        containsAll(<String>{'profiles', 'entries', 'media', 'settings'}),
      );
    });

    test('creates the profile date index', () async {
      final rows = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );

      expect(
        rows.map((row) => row['name']),
        contains('entries_profile_date_idx'),
      );
    });

    test('defines all columns, required fields, and defaults', () async {
      final profiles = await _tableInfo(database, 'profiles');
      final entries = await _tableInfo(database, 'entries');
      final media = await _tableInfo(database, 'media');
      final settings = await _tableInfo(database, 'settings');

      expect(
        profiles.keys,
        orderedEquals(<String>[
          'id',
          'name',
          'avatar_path',
          'created_at',
          'updated_at',
          'is_default',
          'is_archived',
        ]),
      );
      expect(
        entries.keys,
        orderedEquals(<String>[
          'id',
          'profile_id',
          'text',
          'created_at',
          'updated_at',
          'local_date',
          'timezone_offset_minutes',
          'status',
        ]),
      );
      expect(
        media.keys,
        orderedEquals(<String>[
          'id',
          'entry_id',
          'type',
          'relative_path',
          'thumbnail_path',
          'original_filename',
          'mime_type',
          'file_size',
          'width',
          'height',
          'duration_ms',
          'caption',
          'checksum_sha256',
          'created_at',
        ]),
      );
      expect(settings.keys, orderedEquals(<String>['key', 'value']));

      _expectTypes(profiles, <String, String>{
        'id': 'TEXT',
        'name': 'TEXT',
        'avatar_path': 'TEXT',
        'created_at': 'TEXT',
        'updated_at': 'TEXT',
        'is_default': 'INTEGER',
        'is_archived': 'INTEGER',
      });
      _expectTypes(entries, <String, String>{
        'id': 'TEXT',
        'profile_id': 'TEXT',
        'text': 'TEXT',
        'created_at': 'TEXT',
        'updated_at': 'TEXT',
        'local_date': 'TEXT',
        'timezone_offset_minutes': 'INTEGER',
        'status': 'TEXT',
      });
      _expectTypes(media, <String, String>{
        'id': 'TEXT',
        'entry_id': 'TEXT',
        'type': 'TEXT',
        'relative_path': 'TEXT',
        'thumbnail_path': 'TEXT',
        'original_filename': 'TEXT',
        'mime_type': 'TEXT',
        'file_size': 'INTEGER',
        'width': 'INTEGER',
        'height': 'INTEGER',
        'duration_ms': 'INTEGER',
        'caption': 'TEXT',
        'checksum_sha256': 'TEXT',
        'created_at': 'TEXT',
      });
      _expectTypes(settings, <String, String>{'key': 'TEXT', 'value': 'TEXT'});

      _expectNotNull(profiles, <String>[
        'name',
        'created_at',
        'updated_at',
        'is_default',
        'is_archived',
      ]);
      _expectNotNull(entries, <String>[
        'profile_id',
        'text',
        'created_at',
        'updated_at',
        'local_date',
        'timezone_offset_minutes',
        'status',
      ]);
      _expectNotNull(media, <String>[
        'entry_id',
        'type',
        'relative_path',
        'original_filename',
        'mime_type',
        'file_size',
        'checksum_sha256',
        'created_at',
      ]);
      _expectNotNull(settings, <String>['value']);

      expect(entries['text']!['dflt_value'], "''");
      expect(profiles['id']!['pk'], 1);
      expect(entries['id']!['pk'], 1);
      expect(media['id']!['pk'], 1);
      expect(settings['key']!['pk'], 1);
    });

    test('defines the profile date index columns in order', () async {
      final rows = await database.rawQuery(
        'PRAGMA index_info(entries_profile_date_idx)',
      );

      expect(
        rows.map((row) => row['name']),
        orderedEquals(<String>['profile_id', 'local_date', 'created_at']),
      );
    });

    test('enables and defines foreign keys', () async {
      final foreignKeysEnabled = await database.rawQuery('PRAGMA foreign_keys');
      final entryForeignKeys = await database.rawQuery(
        'PRAGMA foreign_key_list(entries)',
      );
      final mediaForeignKeys = await database.rawQuery(
        'PRAGMA foreign_key_list(media)',
      );

      expect(foreignKeysEnabled.single['foreign_keys'], 1);
      expect(entryForeignKeys, contains(containsPair('table', 'profiles')));
      expect(
        mediaForeignKeys,
        contains(
          allOf(
            containsPair('table', 'entries'),
            containsPair('on_delete', 'CASCADE'),
          ),
        ),
      );
    });

    test('rejects an entry whose profile does not exist', () async {
      expect(
        () => database.insert('entries', _entryRow(profileId: 'missing')),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('rejects an invalid entry status', () async {
      await database.insert('profiles', _profileRow());

      expect(
        () => database.insert('entries', _entryRow(status: 'invalid')),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('rejects an invalid profile boolean', () async {
      expect(
        () => database.insert('profiles', _profileRow(isDefault: 2)),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('rejects duplicate media relative paths', () async {
      await database.insert('profiles', _profileRow());
      await database.insert('entries', _entryRow());
      await database.insert('media', _mediaRow());

      expect(
        () => database.insert('media', _mediaRow(id: 'media-2')),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('defaults omitted entry text to an empty string', () async {
      await database.insert('profiles', _profileRow());
      final entry = _entryRow()..remove('text');

      await database.insert('entries', entry);
      final row = await database.query(
        'entries',
        where: 'id = ?',
        whereArgs: <Object?>['entry-1'],
      );

      expect(row.single['text'], '');
    });

    test('deleting an entry cascades to its media', () async {
      await database.insert('profiles', _profileRow());
      await database.insert('entries', _entryRow());
      await database.insert('media', _mediaRow());

      await database.delete(
        'entries',
        where: 'id = ?',
        whereArgs: <Object?>['entry-1'],
      );
      final countRows = await database.rawQuery(
        'SELECT COUNT(*) AS media_count FROM media',
      );

      expect(countRows.single['media_count'], 0);
    });

    test('round-trips a Profile through SQLite and model mappings', () async {
      final profile = Profile(
        id: 'profile-1',
        name: 'Alex',
        avatarPath: null,
        createdAt: DateTime.parse('2026-10-12T08:30:00+08:00'),
        updatedAt: DateTime.parse('2026-10-12T01:15:00Z'),
        isDefault: true,
        isArchived: false,
      );

      await database.insert('profiles', profile.toMap());
      final rows = await database.query(
        'profiles',
        where: 'id = ?',
        whereArgs: <Object?>[profile.id],
      );
      final restored = Profile.fromMap(rows.single);

      expect(restored.id, profile.id);
      expect(restored.name, profile.name);
      expect(restored.avatarPath, isNull);
      expect(restored.createdAt, DateTime.utc(2026, 10, 12, 0, 30));
      expect(restored.createdAt.isUtc, isTrue);
      expect(restored.updatedAt, DateTime.utc(2026, 10, 12, 1, 15));
      expect(restored.updatedAt.isUtc, isTrue);
      expect(restored.isDefault, isTrue);
      expect(restored.isArchived, isFalse);
    });
  });

  group('model mappings', () {
    test('Profile round-trips booleans, UTC dates, and a null avatar', () {
      final profile = Profile(
        id: 'profile-1',
        name: 'Alex',
        avatarPath: null,
        createdAt: DateTime.parse('2026-10-12T08:30:00+08:00'),
        updatedAt: DateTime.parse('2026-10-12T01:15:00Z'),
        isDefault: true,
        isArchived: false,
      );

      final map = profile.toMap();
      final restored = Profile.fromMap(map);

      expect(map['avatar_path'], isNull);
      expect(map['created_at'], '2026-10-12T00:30:00.000Z');
      expect(map['is_default'], 1);
      expect(map['is_archived'], 0);
      expect(restored.id, profile.id);
      expect(restored.name, profile.name);
      expect(restored.avatarPath, isNull);
      expect(restored.createdAt, DateTime.utc(2026, 10, 12, 0, 30));
      expect(restored.createdAt.isUtc, isTrue);
      expect(restored.updatedAt, DateTime.utc(2026, 10, 12, 1, 15));
      expect(restored.updatedAt.isUtc, isTrue);
      expect(restored.isDefault, isTrue);
      expect(restored.isArchived, isFalse);
    });

    test('Profile rejects invalid SQLite boolean values', () {
      final validMap = <String, Object?>{
        'id': 'profile-1',
        'name': 'Alex',
        'avatar_path': null,
        'created_at': '2026-10-12T00:30:00.000Z',
        'updated_at': '2026-10-12T01:15:00.000Z',
        'is_default': 1,
        'is_archived': 0,
      };

      for (final field in <String>['is_default', 'is_archived']) {
        for (final invalidValue in <Object?>[2, null, '1', 0.0, 1.0]) {
          expect(
            () => Profile.fromMap(<String, Object?>{
              ...validMap,
              field: invalidValue,
            }),
            throwsA(isA<FormatException>()),
            reason: '$field must reject $invalidValue',
          );
        }
      }
    });

    test('JournalEntry round-trips dates, local date, and status', () {
      final entry = JournalEntry(
        id: 'entry-1',
        profileId: 'profile-1',
        text: 'A quiet morning.',
        createdAt: DateTime.parse('2026-10-12T08:00:00+08:00'),
        updatedAt: DateTime.parse('2026-10-12T00:05:00Z'),
        localDate: '2026-10-12',
        timezoneOffsetMinutes: 480,
        status: EntryStatus.published,
      );

      final map = entry.toMap();
      final restored = JournalEntry.fromMap(map);

      expect(map['created_at'], '2026-10-12T00:00:00.000Z');
      expect(map['local_date'], '2026-10-12');
      expect(map['status'], 'published');
      expect(restored.id, entry.id);
      expect(restored.profileId, entry.profileId);
      expect(restored.text, entry.text);
      expect(restored.createdAt, DateTime.utc(2026, 10, 12));
      expect(restored.createdAt.isUtc, isTrue);
      expect(restored.updatedAt, DateTime.utc(2026, 10, 12, 0, 5));
      expect(restored.updatedAt.isUtc, isTrue);
      expect(restored.localDate, '2026-10-12');
      expect(restored.timezoneOffsetMinutes, 480);
      expect(restored.status, EntryStatus.published);
    });

    test('MediaItem round-trips enums, UTC dates, and nullable fields', () {
      final media = MediaItem(
        id: 'media-1',
        entryId: 'entry-1',
        type: MediaType.video,
        relativePath: 'media/video.mp4',
        thumbnailPath: null,
        originalFilename: 'original.mp4',
        mimeType: 'video/mp4',
        fileSize: 4096,
        width: null,
        height: null,
        durationMilliseconds: 1250,
        caption: null,
        checksumSha256: 'abc123',
        createdAt: DateTime.parse('2026-10-12T08:00:00+08:00'),
      );

      final map = media.toMap();
      final restored = MediaItem.fromMap(map);

      expect(map['type'], 'video');
      expect(map['thumbnail_path'], isNull);
      expect(map['width'], isNull);
      expect(map['height'], isNull);
      expect(map['duration_ms'], 1250);
      expect(map['caption'], isNull);
      expect(map['created_at'], '2026-10-12T00:00:00.000Z');
      expect(restored.id, media.id);
      expect(restored.entryId, media.entryId);
      expect(restored.type, MediaType.video);
      expect(restored.relativePath, media.relativePath);
      expect(restored.thumbnailPath, isNull);
      expect(restored.originalFilename, media.originalFilename);
      expect(restored.mimeType, media.mimeType);
      expect(restored.fileSize, media.fileSize);
      expect(restored.width, isNull);
      expect(restored.height, isNull);
      expect(restored.durationMilliseconds, 1250);
      expect(restored.caption, isNull);
      expect(restored.checksumSha256, media.checksumSha256);
      expect(restored.createdAt, DateTime.utc(2026, 10, 12));
      expect(restored.createdAt.isUtc, isTrue);
    });
  });
}

Future<Map<String, Map<String, Object?>>> _tableInfo(
  Database database,
  String table,
) async {
  final rows = await database.rawQuery('PRAGMA table_info($table)');
  return <String, Map<String, Object?>>{
    for (final row in rows) row['name']! as String: row,
  };
}

void _expectNotNull(
  Map<String, Map<String, Object?>> tableInfo,
  List<String> columns,
) {
  for (final column in columns) {
    expect(
      tableInfo[column]!['notnull'],
      1,
      reason: '$column must be NOT NULL',
    );
  }
}

void _expectTypes(
  Map<String, Map<String, Object?>> tableInfo,
  Map<String, String> expectedTypes,
) {
  for (final MapEntry(:key, :value) in expectedTypes.entries) {
    expect(
      tableInfo[key]!['type'],
      value,
      reason: '$key must use SQLite type $value',
    );
  }
}

Map<String, Object?> _profileRow({int isDefault = 1}) {
  return <String, Object?>{
    'id': 'profile-1',
    'name': 'Alex',
    'avatar_path': null,
    'created_at': '2026-10-12T00:00:00.000Z',
    'updated_at': '2026-10-12T00:00:00.000Z',
    'is_default': isDefault,
    'is_archived': 0,
  };
}

Map<String, Object?> _entryRow({
  String profileId = 'profile-1',
  String status = 'published',
}) {
  return <String, Object?>{
    'id': 'entry-1',
    'profile_id': profileId,
    'text': 'A quiet morning.',
    'created_at': '2026-10-12T00:00:00.000Z',
    'updated_at': '2026-10-12T00:00:00.000Z',
    'local_date': '2026-10-12',
    'timezone_offset_minutes': 480,
    'status': status,
  };
}

Map<String, Object?> _mediaRow({String id = 'media-1'}) {
  return <String, Object?>{
    'id': id,
    'entry_id': 'entry-1',
    'type': 'image',
    'relative_path': 'media/image.jpg',
    'thumbnail_path': null,
    'original_filename': 'image.jpg',
    'mime_type': 'image/jpeg',
    'file_size': 4096,
    'width': 640,
    'height': 480,
    'duration_ms': null,
    'caption': null,
    'checksum_sha256': 'abc123',
    'created_at': '2026-10-12T00:00:00.000Z',
  };
}
