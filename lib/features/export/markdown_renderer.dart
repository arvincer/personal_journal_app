import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/export/export_models.dart';

class MarkdownRenderer {
  String renderDay({
    required String profileName,
    required String localDate,
    required List<ExportEntry> entries,
    required bool includeOriginalVideos,
  }) {
    final date = _parseLocalDate(localDate);
    final ordered = List<ExportEntry>.of(entries)
      ..sort(
        (left, right) => left.entry.createdAt.compareTo(right.entry.createdAt),
      );
    final output = StringBuffer()
      ..writeln('# ${date.year}年${date.month}月${date.day}日')
      ..writeln()
      ..writeln('人物：${_escapeInline(profileName)}');

    for (final exportEntry in ordered) {
      final entry = exportEntry.entry;
      final localTime = entry.createdAt.toUtc().add(
        Duration(minutes: entry.timezoneOffsetMinutes),
      );
      output
        ..writeln()
        ..writeln(
          '## ${localTime.hour.toString().padLeft(2, '0')}:'
          '${localTime.minute.toString().padLeft(2, '0')}',
        );
      if (entry.text.trim().isNotEmpty) {
        output
          ..writeln()
          ..writeln(entry.text.trim());
      }
      for (final media in exportEntry.media) {
        if (media.item.type == MediaType.image) {
          _writeImage(output, media);
        } else {
          _writeVideo(output, media, includeOriginalVideos);
        }
      }
    }
    return output.toString();
  }

  void _writeImage(StringBuffer output, ExportMediaReference media) {
    final label = _escapeInline(_captionOr(media, '图片'));
    output
      ..writeln()
      ..writeln('![$label](${_portablePath(media.exportPath)})');
  }

  void _writeVideo(
    StringBuffer output,
    ExportMediaReference media,
    bool includeOriginalVideos,
  ) {
    final caption = media.item.caption?.trim();
    if (caption != null && caption.isNotEmpty) {
      output
        ..writeln()
        ..writeln('说明：${_escapeInline(caption)}');
    }
    final duration = media.item.durationMilliseconds;
    if (duration != null) {
      output
        ..writeln()
        ..writeln('时长：${_duration(duration)}');
    }
    final thumbnailPath = media.thumbnailExportPath;
    if (thumbnailPath != null) {
      final suffix = caption == null || caption.isEmpty
          ? ''
          : '：${_escapeInline(caption)}';
      output
        ..writeln()
        ..writeln('![视频预览$suffix](${_portablePath(thumbnailPath)})');
    }
    output.writeln();
    if (includeOriginalVideos) {
      final suffix = caption == null || caption.isEmpty
          ? ''
          : '：${_escapeInline(caption)}';
      output.writeln('[查看原始视频$suffix](${_portablePath(media.exportPath)})');
    } else {
      output.writeln('原视频未包含在本次导出');
    }
  }
}

DateTime _parseLocalDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw FormatException('Expected localDate as YYYY-MM-DD, got $value.');
  }
  final date = DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if (_dateKey(date) != value) {
    throw FormatException('Invalid calendar date: $value.');
  }
  return date;
}

String _captionOr(ExportMediaReference media, String fallback) {
  final caption = media.item.caption?.trim();
  return caption == null || caption.isEmpty ? fallback : caption;
}

String _portablePath(String value) {
  final normalized = value.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(normalized)) {
    throw ArgumentError.value(value, 'path', 'must be relative');
  }
  return normalized;
}

String _escapeInline(String value) => value
    .replaceAll(RegExp(r'[\r\n]+'), ' ')
    .replaceAll('\\', r'\\')
    .replaceAll('*', r'\*')
    .replaceAll('_', r'\_')
    .replaceAll('[', r'\[')
    .replaceAll(']', r'\]')
    .replaceAll('#', r'\#')
    .replaceAll('`', r'\`');

String _duration(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final minuteText = minutes.toString().padLeft(2, '0');
  final secondText = seconds.toString().padLeft(2, '0');
  if (hours == 0) return '$minuteText:$secondText';
  return '${hours.toString().padLeft(2, '0')}:$minuteText:$secondText';
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
