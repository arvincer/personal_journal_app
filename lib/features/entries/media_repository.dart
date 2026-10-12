import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:sqflite/sqflite.dart';

abstract interface class MediaRepository {
  Future<void> insert(MediaItem item);
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
}
