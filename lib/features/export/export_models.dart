import 'dart:collection';

import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';

enum ExportRangePreset { lastSevenDays, currentMonth, all, custom }

class AnalysisExportRequest {
  AnalysisExportRequest({
    required Set<String> profileIds,
    required this.from,
    required this.to,
    required this.includeOriginalVideos,
  }) : profileIds = UnmodifiableSetView<String>(Set<String>.of(profileIds)) {
    if (profileIds.isEmpty) {
      throw ArgumentError.value(profileIds, 'profileIds', 'must not be empty');
    }
    if (to.isBefore(from)) {
      throw ArgumentError.value(to, 'to', 'must not be before from');
    }
  }

  final Set<String> profileIds;
  final DateTime from;
  final DateTime to;
  final bool includeOriginalVideos;
}

class ExportMediaReference {
  const ExportMediaReference({
    required this.item,
    required this.exportPath,
    this.thumbnailExportPath,
  });

  final MediaItem item;
  final String exportPath;
  final String? thumbnailExportPath;
}

class ExportEntry {
  ExportEntry({required this.entry, required List<ExportMediaReference> media})
    : media = List<ExportMediaReference>.unmodifiable(media);

  final JournalEntry entry;
  final List<ExportMediaReference> media;
}

class ExportProfileReference {
  const ExportProfileReference({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name};
}

class AnalysisExportManifest {
  AnalysisExportManifest({
    required this.appVersion,
    required this.exportedAt,
    required List<ExportProfileReference> profiles,
    required this.from,
    required this.to,
    required this.entryCount,
    required this.mediaCount,
  }) : profiles = List<ExportProfileReference>.unmodifiable(profiles) {
    if (entryCount < 0 || mediaCount < 0) {
      throw ArgumentError('Export counts must not be negative.');
    }
    if (to.isBefore(from)) {
      throw ArgumentError.value(to, 'to', 'must not be before from');
    }
  }

  static const int currentFormatVersion = 1;

  final String appVersion;
  final DateTime exportedAt;
  final List<ExportProfileReference> profiles;
  final DateTime from;
  final DateTime to;
  final int entryCount;
  final int mediaCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'format_version': currentFormatVersion,
    'app_version': appVersion,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'selected_profiles': profiles
        .map((profile) => profile.toJson())
        .toList(growable: false),
    'date_range': <String, Object?>{'from': _date(from), 'to': _date(to)},
    'entry_count': entryCount,
    'media_count': mediaCount,
  };
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
