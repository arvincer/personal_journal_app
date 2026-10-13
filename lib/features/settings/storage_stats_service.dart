import 'dart:io';

import 'package:path/path.dart' as path;

typedef StorageDirectoryProvider = Future<Directory> Function();

abstract interface class StorageStatsLoader {
  Future<StorageStats> scan();
}

class StorageStats {
  const StorageStats({
    required this.databaseBytes,
    required this.imageBytes,
    required this.videoBytes,
    required this.thumbnailBytes,
    required this.temporaryBytes,
  });

  final int databaseBytes;
  final int imageBytes;
  final int videoBytes;
  final int thumbnailBytes;
  final int temporaryBytes;

  int get totalBytes =>
      databaseBytes + imageBytes + videoBytes + thumbnailBytes + temporaryBytes;
}

final class StorageStatsService implements StorageStatsLoader {
  StorageStatsService({
    required this.supportDirectoryProvider,
    required this.temporaryDirectoryProvider,
    this.databaseFilename = 'journal.db',
  });

  final StorageDirectoryProvider supportDirectoryProvider;
  final StorageDirectoryProvider temporaryDirectoryProvider;
  final String databaseFilename;

  @override
  Future<StorageStats> scan() async {
    final support = await supportDirectoryProvider();
    final temporary = await temporaryDirectoryProvider();
    return StorageStats(
      databaseBytes: await _databaseBytes(support),
      imageBytes: await _directoryBytes(
        Directory(path.join(support.path, 'media', 'images')),
      ),
      videoBytes: await _directoryBytes(
        Directory(path.join(support.path, 'media', 'videos')),
      ),
      thumbnailBytes: await _directoryBytes(
        Directory(path.join(support.path, 'media', 'thumbnails')),
      ),
      temporaryBytes: await _directoryBytes(temporary),
    );
  }

  Future<int> _databaseBytes(Directory support) async {
    if (!await support.exists()) return 0;
    var total = 0;
    await for (final entity in support.list(followLinks: false)) {
      final filename = path.basename(entity.path);
      if (filename != databaseFilename &&
          filename != '$databaseFilename-wal' &&
          filename != '$databaseFilename-shm') {
        continue;
      }
      if (await FileSystemEntity.type(entity.path, followLinks: false) ==
          FileSystemEntityType.file) {
        total += await File(entity.path).length();
      }
    }
    return total;
  }

  Future<int> _directoryBytes(Directory directory) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) ==
          FileSystemEntityType.file) {
        total += await File(entity.path).length();
      }
    }
    return total;
  }
}
