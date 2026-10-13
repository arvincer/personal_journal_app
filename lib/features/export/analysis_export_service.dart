import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/zip_service.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:personal_journal_app/features/export/export_models.dart';
import 'package:personal_journal_app/features/export/markdown_renderer.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';

typedef ExportDirectoryProvider = Future<Directory> Function();
typedef ExportedAtProvider = DateTime Function();

abstract interface class AnalysisExporter {
  Future<File> create({
    required AnalysisExportRequest request,
    required List<Profile> profiles,
    required String appVersion,
    required String destinationPath,
    ExportCancellationToken? cancellationToken,
  });
}

final class ExportCancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  void cancel() => _isCancelled = true;
  void throwIfCancelled() {
    if (_isCancelled) throw const ExportCancelledException();
  }
}

final class ExportCancelledException implements Exception {
  const ExportCancelledException();
}

final class AnalysisExportService implements AnalysisExporter {
  AnalysisExportService({
    required this.entryRepository,
    required this.mediaRepository,
    required this.fileStore,
    required this.zipService,
    required this.markdownRenderer,
    required this.temporaryDirectoryProvider,
    ExportedAtProvider? exportedAtProvider,
  }) : _exportedAtProvider = exportedAtProvider ?? DateTime.now;

  final EntryRepository entryRepository;
  final MediaRepository mediaRepository;
  final AppFileStore fileStore;
  final ZipService zipService;
  final MarkdownRenderer markdownRenderer;
  final ExportDirectoryProvider temporaryDirectoryProvider;
  final ExportedAtProvider _exportedAtProvider;

  @override
  Future<File> create({
    required AnalysisExportRequest request,
    required List<Profile> profiles,
    required String appVersion,
    required String destinationPath,
    ExportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final selectedProfiles = _selectedProfiles(request, profiles);
    final entries = await entryRepository.listRange(
      profileIds: selectedProfiles.map((profile) => profile.id).toList(),
      from: request.from,
      to: request.to,
    );
    cancellationToken?.throwIfCancelled();
    final temporaryRoot = await temporaryDirectoryProvider();
    await temporaryRoot.create(recursive: true);
    final staging = Directory(
      path.join(
        temporaryRoot.path,
        'analysis-export-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await staging.create();
    try {
      await _writeText(
        File(path.join(staging.path, 'README.md')),
        '# Personal Journal\n\n此资料包供用户选择的 AI 工具读取。\n',
      );
      var mediaCount = 0;
      final multiple = selectedProfiles.length > 1;
      for (final profile in selectedProfiles) {
        cancellationToken?.throwIfCancelled();
        final profileRoot = multiple
            ? Directory(path.join(staging.path, 'profiles', profile.id))
            : staging;
        final profileEntries = entries
            .where((entry) => entry.profileId == profile.id)
            .toList(growable: false);
        await _writeProfile(profileRoot, profile, multiple: multiple);
        final orderedDates =
            profileEntries.map((entry) => entry.localDate).toSet().toList()
              ..sort();
        for (final localDate in orderedDates) {
          cancellationToken?.throwIfCancelled();
          final dayEntries = profileEntries
              .where((entry) => entry.localDate == localDate)
              .toList(growable: false);
          final exportedEntries = <ExportEntry>[];
          for (final entry in dayEntries) {
            cancellationToken?.throwIfCancelled();
            final media = await mediaRepository.listForEntry(entry.id);
            mediaCount += media.length;
            exportedEntries.add(
              ExportEntry(
                entry: entry,
                media: await _copyMedia(
                  profileRoot,
                  localDate,
                  media,
                  request.includeOriginalVideos,
                ),
              ),
            );
          }
          final markdown = markdownRenderer.renderDay(
            profileName: profile.name,
            localDate: localDate,
            entries: exportedEntries,
            includeOriginalVideos: request.includeOriginalVideos,
          );
          await _writeText(
            File(path.join(profileRoot.path, 'days', '$localDate.md')),
            markdown,
          );
        }
      }
      final manifest = AnalysisExportManifest(
        appVersion: appVersion,
        exportedAt: _exportedAtProvider(),
        profiles: selectedProfiles
            .map(
              (profile) =>
                  ExportProfileReference(id: profile.id, name: profile.name),
            )
            .toList(growable: false),
        from: request.from,
        to: request.to,
        entryCount: entries.length,
        mediaCount: mediaCount,
      );
      await _writeText(
        File(path.join(staging.path, 'manifest.json')),
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      );
      cancellationToken?.throwIfCancelled();
      final archive = await zipService.create(
        stagingDirectory: staging,
        destinationPath: destinationPath,
      );
      if (cancellationToken?.isCancelled ?? false) {
        try {
          if (await archive.exists()) await archive.delete();
        } finally {
          cancellationToken!.throwIfCancelled();
        }
      }
      return archive;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  List<Profile> _selectedProfiles(
    AnalysisExportRequest request,
    List<Profile> profiles,
  ) {
    final byId = <String, Profile>{
      for (final profile in profiles) profile.id: profile,
    };
    final selected = <Profile>[];
    for (final id in request.profileIds.toList()..sort()) {
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(id)) {
        throw ArgumentError.value(
          id,
          'profileIds',
          'Invalid profile identifier.',
        );
      }
      final profile = byId[id];
      if (profile == null) throw StateError('Unknown profile "$id".');
      selected.add(profile);
    }
    return selected;
  }

  Future<void> _writeProfile(
    Directory profileRoot,
    Profile profile, {
    required bool multiple,
  }) async {
    final file = multiple
        ? File(path.join(profileRoot.path, 'profile.json'))
        : File(path.join(profileRoot.path, 'profiles', 'profile.json'));
    await _writeText(
      file,
      const JsonEncoder.withIndent(' ')
          .convert(<String, Object?>{'id': profile.id, 'name': profile.name}),
    );
  }

  Future<List<ExportMediaReference>> _copyMedia(
    Directory profileRoot,
    String localDate,
    List<MediaItem> media,
    bool includeOriginalVideos,
  ) async {
    final result = <ExportMediaReference>[];
    for (final item in media) {
      final originalName = path.basename(item.relativePath);
      final originalRelative = 'media/$localDate/$originalName';
      if (item.type == MediaType.image || includeOriginalVideos) {
        await _copyPrivateFile(
          item.relativePath,
          File(
            path.joinAll(<String>[
              profileRoot.path,
              ...originalRelative.split('/'),
            ]),
          ),
        );
      }
      String? thumbnailRelative;
      if (item.thumbnailPath case final thumbnailPath?) {
        final extension = path.extension(thumbnailPath);
        thumbnailRelative =
            'media/$localDate/${path.basenameWithoutExtension(item.relativePath)}-thumbnail$extension';
        await _copyPrivateFile(
          thumbnailPath,
          File(
            path.joinAll(<String>[
              profileRoot.path,
              ...thumbnailRelative.split('/'),
            ]),
          ),
        );
      }
      result.add(
        ExportMediaReference(
          item: item,
          exportPath: '../$originalRelative',
          thumbnailExportPath: thumbnailRelative == null
              ? null
              : '../$thumbnailRelative',
        ),
      );
    }
    return result;
  }

  Future<void> _copyPrivateFile(String relativePath, File target) async {
    final source = await fileStore.resolve(relativePath);
    if (!await source.exists()) {
      throw FileSystemException('Export media is missing.', source.path);
    }
    await target.parent.create(recursive: true);
    if (await target.exists()) {
      throw FileSystemException('Duplicate export media path.', target.path);
    }
    await source.copy(target.path);
  }

  Future<void> _writeText(File file, String value) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }
}
