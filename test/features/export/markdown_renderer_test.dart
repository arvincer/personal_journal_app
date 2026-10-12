import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/export/export_models.dart';
import 'package:personal_journal_app/features/export/markdown_renderer.dart';

void main() {
  test('renders portable markdown with escaped labels and omitted video', () {
    final renderer = MarkdownRenderer();
    final markdown = renderer.renderDay(
      profileName: '孩子 #1',
      localDate: '2026-10-12',
      includeOriginalVideos: false,
      entries: <ExportEntry>[
        ExportEntry(
          entry: _entry('late', '晚上记录了一段训练视频。', 12, 18),
          media: <ExportMediaReference>[
            ExportMediaReference(
              item: _media(
                id: 'video',
                entryId: 'late',
                type: MediaType.video,
                path: r'media\videos\training.mp4',
                thumbnailPath: r'media\thumbnails\training.jpg',
                caption: '训练 *视频*',
                durationMilliseconds: 125000,
              ),
              exportPath: r'..\media\2026-10-12\training.mp4',
              thumbnailExportPath:
                  r'..\media\2026-10-12\training-thumbnail.jpg',
            ),
          ],
        ),
        ExportEntry(
          entry: _entry('early', '今天完成了 **第一版**。', 1, 20),
          media: <ExportMediaReference>[
            ExportMediaReference(
              item: _media(
                id: 'image-1',
                entryId: 'early',
                type: MediaType.image,
                path: r'media\images\sketch.jpg',
                caption: '产品[草图]',
              ),
              exportPath: r'..\media\2026-10-12\sketch.jpg',
            ),
            ExportMediaReference(
              item: _media(
                id: 'image-2',
                entryId: 'early',
                type: MediaType.image,
                path: 'media/images/desk.jpg',
              ),
              exportPath: '../media/2026-10-12/desk.jpg',
            ),
          ],
        ),
      ],
    );

    expect(
      markdown,
      '# 2026年10月12日\n'
      '\n'
      '人物：孩子 \\#1\n'
      '\n'
      '## 09:20\n'
      '\n'
      '今天完成了 **第一版**。\n'
      '\n'
      '![产品\\[草图\\]](../media/2026-10-12/sketch.jpg)\n'
      '\n'
      '![图片](../media/2026-10-12/desk.jpg)\n'
      '\n'
      '## 20:18\n'
      '\n'
      '晚上记录了一段训练视频。\n'
      '\n'
      '说明：训练 \\*视频\\*\n'
      '\n'
      '时长：02:05\n'
      '\n'
      '![视频预览：训练 \\*视频\\*]'
      '(../media/2026-10-12/training-thumbnail.jpg)\n'
      '\n'
      '原视频未包含在本次导出\n',
    );
  });

  test('links the original video when requested', () {
    final markdown = MarkdownRenderer().renderDay(
      profileName: '我的日志',
      localDate: '2026-10-12',
      includeOriginalVideos: true,
      entries: <ExportEntry>[
        ExportEntry(
          entry: _entry('entry', '视频', 12, 18),
          media: <ExportMediaReference>[
            ExportMediaReference(
              item: _media(
                id: 'video',
                entryId: 'entry',
                type: MediaType.video,
                path: 'media/videos/training.mp4',
                thumbnailPath: 'media/thumbnails/training.jpg',
                caption: '训练',
                durationMilliseconds: 1000,
              ),
              exportPath: '../media/2026-10-12/training.mp4',
              thumbnailExportPath: '../media/2026-10-12/training-thumbnail.jpg',
            ),
          ],
        ),
      ],
    );

    expect(markdown, contains('[查看原始视频：训练](../media/2026-10-12/training.mp4)'));
    expect(markdown, isNot(contains('原视频未包含在本次导出')));
  });

  test('serializes a versioned analysis export manifest', () {
    final manifest = AnalysisExportManifest(
      appVersion: '1.2.3',
      exportedAt: DateTime.utc(2026, 10, 12, 12, 30),
      profiles: const <ExportProfileReference>[
        ExportProfileReference(id: 'p1', name: '我的日志'),
      ],
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 12),
      entryCount: 3,
      mediaCount: 4,
    );

    expect(manifest.toJson(), <String, Object?>{
      'format_version': 1,
      'app_version': '1.2.3',
      'exported_at': '2026-10-12T12:30:00.000Z',
      'selected_profiles': <Object?>[
        <String, Object?>{'id': 'p1', 'name': '我的日志'},
      ],
      'date_range': <String, Object?>{'from': '2026-10-01', 'to': '2026-10-12'},
      'entry_count': 3,
      'media_count': 4,
    });
  });

  test('rejects an absolute file URI', () {
    expect(
      () => MarkdownRenderer().renderDay(
        profileName: '我的日志',
        localDate: '2026-10-12',
        includeOriginalVideos: false,
        entries: <ExportEntry>[
          ExportEntry(
            entry: _entry('entry', '图片', 1, 20),
            media: <ExportMediaReference>[
              ExportMediaReference(
                item: _media(
                  id: 'image',
                  entryId: 'entry',
                  type: MediaType.image,
                  path: 'media/images/image.jpg',
                ),
                exportPath: 'file:///private/image.jpg',
              ),
            ],
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('keeps profile names on one escaped metadata line', () {
    final markdown = MarkdownRenderer().renderDay(
      profileName: '我的\n日志',
      localDate: '2026-10-12',
      includeOriginalVideos: false,
      entries: const <ExportEntry>[],
    );

    expect(markdown, contains('人物：我的 日志\n'));
  });
}

JournalEntry _entry(String id, String text, int utcHour, int minute) =>
    JournalEntry(
      id: id,
      profileId: 'profile',
      text: text,
      createdAt: DateTime.utc(2026, 10, 12, utcHour, minute),
      updatedAt: DateTime.utc(2026, 10, 12, utcHour, minute),
      localDate: '2026-10-12',
      timezoneOffsetMinutes: 480,
      status: EntryStatus.published,
    );

MediaItem _media({
  required String id,
  required String entryId,
  required MediaType type,
  required String path,
  String? thumbnailPath,
  String? caption,
  int? durationMilliseconds,
}) => MediaItem(
  id: id,
  entryId: entryId,
  type: type,
  relativePath: path,
  thumbnailPath: thumbnailPath,
  originalFilename: path.split(RegExp(r'[/\\]')).last,
  mimeType: type == MediaType.image ? 'image/jpeg' : 'video/mp4',
  fileSize: 10,
  width: 100,
  height: 100,
  durationMilliseconds: durationMilliseconds,
  caption: caption,
  checksumSha256: 'checksum',
  createdAt: DateTime.utc(2026, 10, 12),
);
