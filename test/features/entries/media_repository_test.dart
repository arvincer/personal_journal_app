import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('lists an entry media and deletes its database row', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repository = SqliteMediaRepository(database);
    await database.insert('profiles', <String, Object?>{
      'id': 'p',
      'name': 'P',
      'avatar_path': null,
      'created_at': DateTime.utc(2026).toIso8601String(),
      'updated_at': DateTime.utc(2026).toIso8601String(),
      'is_default': 1,
      'is_archived': 0,
    });
    await database.insert('entries', <String, Object?>{
      'id': 'e',
      'profile_id': 'p',
      'text': '',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'updated_at': DateTime.utc(2026).toIso8601String(),
      'local_date': '2026-10-12',
      'timezone_offset_minutes': 480,
      'status': 'draft',
    });
    final item = MediaItem(
      id: 'm',
      entryId: 'e',
      type: MediaType.image,
      relativePath: 'media/images/m.jpg',
      thumbnailPath: null,
      originalFilename: 'm.jpg',
      mimeType: 'image/jpeg',
      fileSize: 1,
      width: null,
      height: null,
      durationMilliseconds: null,
      caption: null,
      checksumSha256: 'x',
      createdAt: DateTime.utc(2026),
    );
    await repository.insert(item);
    expect((await repository.listForEntry('e')).single.id, 'm');
    await repository.delete('m');
    expect(await repository.listForEntry('e'), isEmpty);
  });
}
