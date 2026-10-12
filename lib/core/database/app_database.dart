import 'package:sqflite/sqflite.dart';

abstract final class AppDatabase {
  static Future<Database> open({
    DatabaseFactory? factory,
    required String path,
  }) {
    return (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await database.execute('''
CREATE TABLE profiles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  avatar_path TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  is_default INTEGER NOT NULL CHECK (is_default IN (0, 1)),
  is_archived INTEGER NOT NULL CHECK (is_archived IN (0, 1))
);
''');
          await database.execute('''
CREATE TABLE entries (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id),
  text TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  local_date TEXT NOT NULL,
  timezone_offset_minutes INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('draft', 'published'))
);
''');
          await database.execute('''
CREATE INDEX entries_profile_date_idx
ON entries(profile_id, local_date, created_at);
''');
          await database.execute('''
CREATE TABLE media (
  id TEXT PRIMARY KEY,
  entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('image', 'video')),
  relative_path TEXT NOT NULL UNIQUE,
  thumbnail_path TEXT,
  original_filename TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  width INTEGER,
  height INTEGER,
  duration_ms INTEGER,
  caption TEXT,
  checksum_sha256 TEXT NOT NULL,
  created_at TEXT NOT NULL
);
''');
          await database.execute('''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''');
        },
      ),
    );
  }
}
