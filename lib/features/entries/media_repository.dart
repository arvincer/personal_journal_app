import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:sqflite/sqflite.dart';

abstract interface class MediaRepository {
  Future<void> insert(MediaItem item);
  Future<List<MediaItem>> listForEntry(String entryId);
  Future<void> delete(String mediaId);
  Future<void> updateCaption({required String mediaId, required String? caption});
}

final class SqliteMediaRepository implements MediaRepository {
  const SqliteMediaRepository(this._database);

  final Database _database;

  @override
  Future<void> insert(MediaItem item) {
    return _database.transaction((transaction) async {
      await transaction.insert('media', item.toMap());
    });
  }

  @override
  Future<List<MediaItem>> listForEntry(String entryId) async {
    final rows = await _database.query(
      'media',
      where: 'entry_id = ?',
      whereArgs: <Object?>[entryId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(MediaItem.fromMap).toList(growable: false);
  }

  @override
  Future<void> delete(String mediaId) => _database.delete(
        'media',
        where: 'id = ?',
        whereArgs: <Object?>[mediaId],
      ).then((_) {});

  @override
  Future<void> updateCaption({
    required String mediaId,
    required String? caption,
  }) => _database.update(
        'media',
        <String, Object?>{'caption': caption},
        where: 'id = ?',
        whereArgs: <Object?>[mediaId],
      ).then((_) {});
}
