import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/platform/media_picker.dart';
import 'package:personal_journal_app/features/entries/media_import_service.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';

void main() {
  group('MediaImportService', () {
    late Directory sandbox;
    late Directory support;
    late Directory temporary;
    late AppFileStore fileStore;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('journal-media-import-');
      support = Directory('${sandbox.path}${Platform.pathSeparator}support');
      temporary = Directory(
        '${sandbox.path}${Platform.pathSeparator}temporary',
      );
      fileStore = AppFileStore(
        supportDirectoryProvider: () async => support,
        temporaryDirectoryProvider: () async => temporary,
      );
    });

    tearDown(() => sandbox.delete(recursive: true));

    test(
      'imports an image into private storage with complete metadata',
      () async {
        final source = await _source(sandbox, 'summer.jpg', <int>[4, 5, 6]);
        final repository = _RecordingMediaRepository();
        final service = MediaImportService(
          fileStore: fileStore,
          repository: repository,
          mediaIdProvider: () => 'm1',
          now: () => DateTime.utc(2026, 10, 12),
        );

        final item = await service.importMedia(
          entryId: 'entry-1',
          media: PickedMedia.image(source.path, originalFilename: 'summer.jpg'),
        );

        expect(item.type, MediaType.image);
        expect(item.mimeType, 'image/jpeg');
        expect(item.fileSize, 3);
        expect(item.relativePath, 'media/images/m1.jpg');
        expect(item.checksumSha256, isNotEmpty);
        expect(item.thumbnailPath, isNull);
        expect(repository.inserted, same(item));
        expect(
          await (await fileStore.resolve(item.relativePath)).readAsBytes(),
          <int>[4, 5, 6],
        );
        expect(await _stagingFiles(temporary), isEmpty);
      },
    );

    test(
      'cleans staging and permanent files when repository insert throws',
      () async {
        final source = await _source(sandbox, 'summer.jpg', <int>[4, 5, 6]);
        final service = MediaImportService(
          fileStore: fileStore,
          repository: _ThrowingMediaRepository(),
          mediaIdProvider: () => 'm1',
        );

        await expectLater(
          service.importMedia(
            entryId: 'entry-1',
            media: PickedMedia.image(
              source.path,
              originalFilename: 'summer.jpg',
            ),
          ),
          throwsStateError,
        );

        expect(await _stagingFiles(temporary), isEmpty);
        expect(await support.list(recursive: true).toList(), isEmpty);
      },
    );

    test('imports video with a generated private thumbnail', () async {
      final source = await _source(sandbox, 'walk.mp4', <int>[7, 8, 9, 10]);
      final thumbnailSource = await _source(
        sandbox,
        'generated-thumb.jpg',
        <int>[2, 4],
      );
      final repository = _RecordingMediaRepository();
      final service = MediaImportService(
        fileStore: fileStore,
        repository: repository,
        thumbnailGenerator: _FakeThumbnailGenerator(thumbnailSource.path),
        mediaIdProvider: () => 'v1',
      );

      final item = await service.importMedia(
        entryId: 'entry-1',
        media: PickedMedia.video(source.path, originalFilename: 'walk.mp4'),
      );

      expect(item.type, MediaType.video);
      expect(item.mimeType, 'video/mp4');
      expect(item.fileSize, 4);
      expect(item.relativePath, 'media/videos/v1.mp4');
      expect(item.thumbnailPath, 'media/thumbnails/v1.jpg');
      expect(
        await (await fileStore.resolve(item.thumbnailPath!)).readAsBytes(),
        <int>[2, 4],
      );
      expect(await _stagingFiles(temporary), isEmpty);
    });
  });
}

Future<File> _source(Directory directory, String name, List<int> bytes) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file;
}

Future<List<FileSystemEntity>> _stagingFiles(Directory temporary) async {
  final staging = Directory(
    '${temporary.path}${Platform.pathSeparator}staging',
  );
  if (!await staging.exists()) {
    return const <FileSystemEntity>[];
  }
  return staging.list(recursive: true).toList();
}

final class _RecordingMediaRepository implements MediaRepository {
  MediaItem? inserted;

  @override
  Future<void> insert(MediaItem item) async {
    inserted = item;
  }
  @override
  Future<void> delete(String mediaId) async {}
  @override
  Future<List<MediaItem>> listForEntry(String entryId) async => const <MediaItem>[];
  @override
  Future<void> updateCaption({required String mediaId, required String? caption}) async {}
}

final class _ThrowingMediaRepository implements MediaRepository {
  @override
  Future<void> insert(MediaItem item) =>
      Future<void>.error(StateError('db failed'));
  @override
  Future<void> delete(String mediaId) async {}
  @override
  Future<List<MediaItem>> listForEntry(String entryId) async => const <MediaItem>[];
  @override
  Future<void> updateCaption({required String mediaId, required String? caption}) async {}
}

final class _FakeThumbnailGenerator implements ThumbnailGenerator {
  const _FakeThumbnailGenerator(this.path);

  final String path;

  @override
  Future<String> generate(String stagedVideoPath) async => path;
}
