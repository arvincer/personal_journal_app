import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/checksum_service.dart';
import 'package:personal_journal_app/core/platform/media_picker.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

abstract interface class ThumbnailGenerator {
  Future<String> generate(String stagedVideoPath);
}

abstract interface class MediaImporter {
  Future<MediaItem> importMedia({
    required String entryId,
    required PickedMedia media,
  });
}

final class PlatformVideoThumbnailGenerator implements ThumbnailGenerator {
  @override
  Future<String> generate(String stagedVideoPath) async {
    final path = await VideoThumbnail.thumbnailFile(
      video: stagedVideoPath,
      thumbnailPath: Directory.systemTemp.path,
      imageFormat: ImageFormat.JPEG,
    );
    if (path == null) throw StateError('Could not generate video thumbnail.');
    return path;
  }
}

typedef MediaIdProvider = String Function();
typedef Now = DateTime Function();

final class MediaImportService implements MediaImporter {
  MediaImportService({
    required this.fileStore,
    required this.repository,
    ChecksumService? checksumService,
    this.thumbnailGenerator,
    MediaIdProvider? mediaIdProvider,
    Now? now,
  }) : _checksumService = checksumService ?? Sha256ChecksumService(),
       _mediaIdProvider = mediaIdProvider ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final AppFileStore fileStore;
  final MediaRepository repository;
  final ChecksumService _checksumService;
  final ThumbnailGenerator? thumbnailGenerator;
  final MediaIdProvider _mediaIdProvider;
  final Now _now;

  @override
  Future<MediaItem> importMedia({
    required String entryId,
    required PickedMedia media,
  }) async {
    File? stagedMedia;
    File? stagedThumbnail;
    final committed = <String>[];
    try {
      stagedMedia = await fileStore.stageCopy(media.path);
      final mediaId = _mediaIdProvider();
      final extension = _extensionFor(media.originalFilename);
      final checksum = await _checksumService.forFile(stagedMedia.path);
      final size = await stagedMedia.length();

      String? thumbnailPath;
      final relativePath = switch (media.type) {
        PickedMediaType.image => await fileStore.commitImage(
          stagedMedia,
          mediaId,
          extension,
        ),
        PickedMediaType.video => await fileStore.commitVideo(
          stagedMedia,
          mediaId,
          extension,
        ),
      };
      committed.add(relativePath);

      if (media.type == PickedMediaType.video) {
        final generator = thumbnailGenerator;
        if (generator == null) {
          throw StateError(
            'A thumbnail generator is required for video imports.',
          );
        }
        final generatedThumbnail = await generator.generate(stagedMedia.path);
        stagedThumbnail = await fileStore.stageCopy(generatedThumbnail);
        thumbnailPath = await fileStore.commitThumbnail(
          stagedThumbnail,
          mediaId,
          _extensionFor(generatedThumbnail),
        );
        committed.add(thumbnailPath);
      }

      final item = MediaItem(
        id: mediaId,
        entryId: entryId,
        type: media.type == PickedMediaType.image
            ? MediaType.image
            : MediaType.video,
        relativePath: relativePath,
        thumbnailPath: thumbnailPath,
        originalFilename: path.basename(media.originalFilename),
        mimeType: _mimeType(media.type, extension),
        fileSize: size,
        width: null,
        height: null,
        durationMilliseconds: null,
        caption: null,
        checksumSha256: checksum,
        createdAt: _now().toUtc(),
      );
      await repository.insert(item);
      return item;
    } catch (error, stackTrace) {
      for (final relativePath in committed.reversed) {
        await _bestEffort(() => fileStore.deleteRelative(relativePath));
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (stagedThumbnail != null) {
        await _bestEffort(() => fileStore.deleteStaged(stagedThumbnail!));
      }
      if (stagedMedia != null) {
        await _bestEffort(() => fileStore.deleteStaged(stagedMedia!));
      }
    }
  }

  Future<void> _bestEffort(Future<void> Function() cleanup) async {
    try {
      await cleanup();
    } catch (_) {
      // Cleanup must not hide the import result or prevent later cleanup.
    }
  }

  String _extensionFor(String fileName) {
    final extension = path.extension(fileName).toLowerCase();
    if (extension.isEmpty) {
      throw ArgumentError.value(
        fileName,
        'fileName',
        'File extension is required.',
      );
    }
    return extension;
  }

  String _mimeType(PickedMediaType type, String extension) {
    final normalized = extension.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
    return switch ((type, normalized)) {
      (PickedMediaType.image, 'jpg' || 'jpeg') => 'image/jpeg',
      (PickedMediaType.image, 'png') => 'image/png',
      (PickedMediaType.image, 'webp') => 'image/webp',
      (PickedMediaType.image, 'heic') => 'image/heic',
      (PickedMediaType.image, 'gif') => 'image/gif',
      (PickedMediaType.video, 'mp4') => 'video/mp4',
      (PickedMediaType.video, 'mov') => 'video/quicktime',
      (PickedMediaType.video, 'm4v') => 'video/x-m4v',
      (PickedMediaType.video, 'webm') => 'video/webm',
      _ => throw ArgumentError.value(
        extension,
        'extension',
        'Unsupported media extension.',
      ),
    };
  }
}
