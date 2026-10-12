enum MediaType { image, video }

class MediaItem {
  const MediaItem({
    required this.id,
    required this.entryId,
    required this.type,
    required this.relativePath,
    required this.thumbnailPath,
    required this.originalFilename,
    required this.mimeType,
    required this.fileSize,
    required this.width,
    required this.height,
    required this.durationMilliseconds,
    required this.caption,
    required this.checksumSha256,
    required this.createdAt,
  });

  final String id;
  final String entryId;
  final MediaType type;
  final String relativePath;
  final String? thumbnailPath;
  final String originalFilename;
  final String mimeType;
  final int fileSize;
  final int? width;
  final int? height;
  final int? durationMilliseconds;
  final String? caption;
  final String checksumSha256;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'entry_id': entryId,
      'type': type.name,
      'relative_path': relativePath,
      'thumbnail_path': thumbnailPath,
      'original_filename': originalFilename,
      'mime_type': mimeType,
      'file_size': fileSize,
      'width': width,
      'height': height,
      'duration_ms': durationMilliseconds,
      'caption': caption,
      'checksum_sha256': checksumSha256,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory MediaItem.fromMap(Map<String, Object?> map) {
    return MediaItem(
      id: map['id'] as String,
      entryId: map['entry_id'] as String,
      type: MediaType.values.byName(map['type'] as String),
      relativePath: map['relative_path'] as String,
      thumbnailPath: map['thumbnail_path'] as String?,
      originalFilename: map['original_filename'] as String,
      mimeType: map['mime_type'] as String,
      fileSize: map['file_size'] as int,
      width: map['width'] as int?,
      height: map['height'] as int?,
      durationMilliseconds: map['duration_ms'] as int?,
      caption: map['caption'] as String?,
      checksumSha256: map['checksum_sha256'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
