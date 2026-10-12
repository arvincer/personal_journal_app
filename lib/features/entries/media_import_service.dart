import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/checksum_service.dart';
import 'package:personal_journal_app/core/platform/media_picker.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class ThumbnailGenerator {
  Future<String> generate(String stagedVideoPath);
}

typedef MediaIdProvider = String Function();
typedef Now = DateTime Function();

final class MediaImportService {
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
    } catch (_) {
      for (final relativePath in committed.reversed) {
        await fileStore.deleteRelative(relativePath);
      }
      rethrow;
    } finally {
      if (stagedThumbnail != null) {
        await fileStore.deleteStaged(stagedThumbnail);
      }
      if (stagedMedia != null) {
        await fileStore.deleteStaged(stagedMedia);
      }
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
