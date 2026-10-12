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
      expect(restored.updatedAt, DateTime.utc(2026, 10, 12, 1, 15));
      expect(restored.isDefault, isTrue);
      expect(restored.isArchived, isFalse);
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
      expect(restored.updatedAt, DateTime.utc(2026, 10, 12, 0, 5));
      expect(restored.localDate, entry.localDate);
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
    });
  });
}
