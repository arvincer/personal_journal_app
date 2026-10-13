import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_journal_app/features/settings/storage_stats_service.dart';

void main() {
  test('totals only known application storage categories', () async {
    final root = await Directory.systemTemp.createTemp('storage-stats-test-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final support = Directory(path.join(root.path, 'support'))
      ..createSync(recursive: true);
    final temporary = Directory(path.join(root.path, 'temporary'))
      ..createSync(recursive: true);
    Future<void> write(String relative, int bytes, {bool temp = false}) async {
      final base = temp ? temporary : support;
      final file = File(path.join(base.path, relative));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(bytes, 1));
    }

    await write('journal.db', 10);
    await write('journal.db-wal', 2);
    await write('media/images/a.jpg', 20);
    await write('media/videos/a.mp4', 30);
    await write('media/thumbnails/a.jpg', 5);
    await write('unmanaged.bin', 99);
    await write('staging/part.bin', 7, temp: true);

    final stats = await StorageStatsService(
      supportDirectoryProvider: () async => support,
      temporaryDirectoryProvider: () async => temporary,
    ).scan();

    expect(stats.databaseBytes, 12);
    expect(stats.imageBytes, 20);
    expect(stats.videoBytes, 30);
    expect(stats.thumbnailBytes, 5);
    expect(stats.temporaryBytes, 7);
    expect(stats.totalBytes, 74);
  });
}
