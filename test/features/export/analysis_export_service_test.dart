import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/zip_service.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:personal_journal_app/features/export/analysis_export_service.dart';
import 'package:personal_journal_app/features/export/export_models.dart';
import 'package:personal_journal_app/features/export/markdown_renderer.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';

void main() {
  late Directory root;
  late Directory support;
  late Directory temporary;
  late AppFileStore fileStore;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('journal-export-test-');
    support = Directory(path.join(root.path, 'support'))..createSync();
    temporary = Directory(path.join(root.path, 'temporary'))..createSync();
    fileStore = AppFileStore(
      supportDirectoryProvider: () async => support,
      temporaryDirectoryProvider: () async => temporary,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  AnalysisExportService service(
    List<JournalEntry> entries,
    List<MediaItem> media,
  ) => AnalysisExportService(
    entryRepository: _Entries(entries),
    mediaRepository: _Media(media),
    fileStore: fileStore,
    zipService: const ZipService(),
    markdownRenderer: MarkdownRenderer(),
    temporaryDirectoryProvider: () async => temporary,
    exportedAtProvider: () => DateTime.utc(2026, 10, 13),
  );

  test(
    'exports one profile with markdown, image and video thumbnail',
    () async {
      await _write(support, 'media/images/image.jpg', 'image');
      await _write(support, 'media/videos/video.mp4', 'video');
      await _write(support, 'media/thumbnails/video.jpg', 'thumb');
      final entry = _entry('e1', 'p1', '记录');
      final media = <MediaItem>[
        _media('i1', 'e1', MediaType.image, 'media/images/image.jpg'),
        _media(
          'v1',
          'e1',
          MediaType.video,
          'media/videos/video.mp4',
          thumbnail: 'media/thumbnails/video.jpg',
        ),
      ];
      final destination = path.join(root.path, 'one.zip');
      final exportService = service(<JournalEntry>[entry], media);

      await exportService.create(
        request: AnalysisExportRequest(
          profileIds: <String>{'p1'},
          from: DateTime(2026, 10, 12),
          to: DateTime(2026, 10, 12),
          includeOriginalVideos: false,
        ),
        profiles: <Profile>[_profile('p1', '我的日志')],
        appVersion: '1.0.0',
        destinationPath: destination,
      );

      final archive = ZipDecoder().decodeBytes(
        await File(destination).readAsBytes(),
      );
      final names = archive.files
          .where((file) => file.isFile)
          .map((e) => e.name);
      expect(
        names,
        containsAll(<String>[
          'README.md',
          'manifest.json',
          'profiles/profile.json',
          'days/2026-10-12.md',
          'media/2026-10-12/image.jpg',
          'media/2026-10-12/video-thumbnail.jpg',
        ]),
      );
      expect(names, isNot(contains('media/2026-10-12/video.mp4')));
      expect(_text(archive, 'days/2026-10-12.md'), contains('原视频未包含在本次导出'));
      expect(await temporary.list().toList(), isEmpty);
    },
  );

  test('separates multiple profiles and includes original videos', () async {
    await _write(support, 'media/videos/video.mp4', 'video');
    await _write(support, 'media/thumbnails/video.jpg', 'thumb');
    final entries = <JournalEntry>[
      _entry('e1', 'p1', '我的'),
      _entry('e2', 'p2', '孩子'),
    ];
    final media = <MediaItem>[
      _media(
        'v1',
        'e2',
        MediaType.video,
        'media/videos/video.mp4',
        thumbnail: 'media/thumbnails/video.jpg',
      ),
    ];
    final destination = path.join(root.path, 'many.zip');

    await service(entries, media).create(
      request: AnalysisExportRequest(
        profileIds: <String>{'p1', 'p2'},
        from: DateTime(2026, 10, 12),
        to: DateTime(2026, 10, 12),
        includeOriginalVideos: true,
      ),
      profiles: <Profile>[_profile('p1', '我的日志'), _profile('p2', '孩子')],
      appVersion: '1.0.0',
      destinationPath: destination,
    );

    final archive = ZipDecoder().decodeBytes(
      await File(destination).readAsBytes(),
    );
    final names = archive.files.where((file) => file.isFile).map((e) => e.name);
    expect(names, contains('profiles/p1/days/2026-10-12.md'));
    expect(names, contains('profiles/p2/days/2026-10-12.md'));
    expect(names, contains('profiles/p2/media/2026-10-12/video.mp4'));
    expect(
      _text(archive, 'profiles/p2/days/2026-10-12.md'),
      contains('[查看原始视频'),
    );
  });

  test('removes staging files when referenced media is missing', () async {
    final entry = _entry('e1', 'p1', '缺失媒体');
    final media = <MediaItem>[
      _media('i1', 'e1', MediaType.image, 'media/images/missing.jpg'),
    ];

    await expectLater(
      service(<JournalEntry>[entry], media).create(
        request: AnalysisExportRequest(
          profileIds: <String>{'p1'},
          from: DateTime(2026, 10, 12),
          to: DateTime(2026, 10, 12),
          includeOriginalVideos: false,
        ),
        profiles: <Profile>[_profile('p1', '我的日志')],
        appVersion: '1.0.0',
        destinationPath: path.join(root.path, 'failed.zip'),
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(await temporary.list().toList(), isEmpty);
    expect(await File(path.join(root.path, 'failed.zip')).exists(), isFalse);
  });
}

class _Entries implements EntryRepository {
  _Entries(this.entries);
  final List<JournalEntry> entries;
  @override
  Future<List<JournalEntry>> listRange({
    required List<String> profileIds,
    required DateTime from,
    required DateTime to,
  }) async => entries.where((e) => profileIds.contains(e.profileId)).toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements MediaRepository {
  _Media(this.media);
  final List<MediaItem> media;
  @override
  Future<List<MediaItem>> listForEntry(String entryId) async =>
      media.where((m) => m.entryId == entryId).toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _write(Directory root, String relative, String content) async {
  final file = File(path.joinAll(<String>[root.path, ...relative.split('/')]));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

String _text(Archive archive, String name) =>
    utf8.decode((archive.findFile(name)!.content as List<int>));

JournalEntry _entry(String id, String profileId, String text) => JournalEntry(
  id: id,
  profileId: profileId,
  text: text,
  createdAt: DateTime.utc(2026, 10, 12, 1, 20),
  updatedAt: DateTime.utc(2026, 10, 12, 1, 20),
  localDate: '2026-10-12',
  timezoneOffsetMinutes: 480,
  status: EntryStatus.published,
);

MediaItem _media(
  String id,
  String entryId,
  MediaType type,
  String relative, {
  String? thumbnail,
}) => MediaItem(
  id: id,
  entryId: entryId,
  type: type,
  relativePath: relative,
  thumbnailPath: thumbnail,
  originalFilename: path.basename(relative),
  mimeType: type == MediaType.image ? 'image/jpeg' : 'video/mp4',
  fileSize: 5,
  width: 10,
  height: 10,
  durationMilliseconds: type == MediaType.video ? 3000 : null,
  caption: null,
  checksumSha256: 'hash',
  createdAt: DateTime.utc(2026, 10, 12),
);

Profile _profile(String id, String name) => Profile(
  id: id,
  name: name,
  avatarPath: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  isDefault: id == 'p1',
  isArchived: false,
);
