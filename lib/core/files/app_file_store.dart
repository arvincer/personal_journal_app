import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef DirectoryProvider = Future<Directory> Function();

final class AppFileStore {
  AppFileStore({
    DirectoryProvider? supportDirectoryProvider,
    DirectoryProvider? temporaryDirectoryProvider,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory;

  static const Set<String> _imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'gif',
  };
  static const Set<String> _videoExtensions = <String>{
    'mp4',
    'mov',
    'm4v',
    'webm',
  };
  static const Set<String> _thumbnailExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  final DirectoryProvider _supportDirectoryProvider;
  final DirectoryProvider _temporaryDirectoryProvider;

  Future<File> stageCopy(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'File does not exist.',
      );
    }
    final staging = await _stagingDirectory();
    final extension = path.extension(source.path).toLowerCase();
    final staged = File(path.join(staging.path, '${_randomName()}$extension'));
    return source.copy(staged.path);
  }

  Future<String> commitImage(File staged, String mediaId, String extension) {
    return _commit(
      staged: staged,
      mediaId: mediaId,
      extension: extension,
      directory: 'media/images',
      allowedExtensions: _imageExtensions,
    );
  }

  Future<String> commitVideo(File staged, String mediaId, String extension) {
    return _commit(
      staged: staged,
      mediaId: mediaId,
      extension: extension,
      directory: 'media/videos',
      allowedExtensions: _videoExtensions,
    );
  }

  Future<String> commitThumbnail(
    File staged,
    String mediaId,
    String extension,
  ) {
    return _commit(
      staged: staged,
      mediaId: mediaId,
      extension: extension,
      directory: 'media/thumbnails',
      allowedExtensions: _thumbnailExtensions,
    );
  }

  Future<void> deleteRelative(String relativePath) async {
    final support = await _supportDirectoryProvider();
    final file = await resolve(relativePath);
    if (await file.exists()) {
      await file.delete();
      await _pruneEmptyParents(file.parent, support);
    }
  }

  Future<File> resolve(String relativePath) async {
    final support = await _supportDirectoryProvider();
    return File(_resolveInside(support.path, relativePath));
  }

  Future<void> deleteStaged(File staged) async {
    final staging = await _stagingDirectory();
    _ensureInside(staging.path, staged.path);
    if (await staged.exists()) {
      await staged.delete();
    }
  }

  Future<String> _commit({
    required File staged,
    required String mediaId,
    required String extension,
    required String directory,
    required Set<String> allowedExtensions,
  }) async {
    _validateMediaId(mediaId);
    final normalizedExtension = _normalizeExtension(
      extension,
      allowedExtensions,
    );
    final staging = await _stagingDirectory();
    _ensureInside(staging.path, staged.path);
    if (!await staged.exists()) {
      throw ArgumentError.value(
        staged.path,
        'staged',
        'Staged file does not exist.',
      );
    }
    final relative = '$directory/$mediaId.$normalizedExtension';
    final target = await resolve(relative);
    await target.parent.create(recursive: true);
    return (await staged.copy(target.path)).path == target.path
        ? relative
        : relative;
  }

  Future<Directory> _stagingDirectory() async {
    final temporary = await _temporaryDirectoryProvider();
    final staging = Directory(path.join(temporary.path, 'staging'));
    await staging.create(recursive: true);
    return staging;
  }

  String _resolveInside(String root, String relativePath) {
    if (relativePath.trim().isEmpty || path.isAbsolute(relativePath)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Path must be relative.',
      );
    }
    final components = path.split(relativePath);
    if (components.any((component) => component == '..')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Path traversal is not allowed.',
      );
    }
    final candidate = path.normalize(path.join(root, relativePath));
    _ensureInside(root, candidate);
    return candidate;
  }

  void _ensureInside(String root, String candidate) {
    final normalizedRoot = path.normalize(path.absolute(root));
    final normalizedCandidate = path.normalize(path.absolute(candidate));
    if (!path.isWithin(normalizedRoot, normalizedCandidate)) {
      throw ArgumentError.value(
        candidate,
        'path',
        'Path escapes the application root.',
      );
    }
  }

  String _normalizeExtension(String extension, Set<String> allowedExtensions) {
    final normalized = extension.trim().toLowerCase().replaceFirst(
      RegExp(r'^\.'),
      '',
    );
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(normalized) ||
        !allowedExtensions.contains(normalized)) {
      throw ArgumentError.value(
        extension,
        'extension',
        'Unsupported file extension.',
      );
    }
    return normalized;
  }

  void _validateMediaId(String mediaId) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(mediaId)) {
      throw ArgumentError.value(
        mediaId,
        'mediaId',
        'Invalid media identifier.',
      );
    }
  }

  Future<void> _pruneEmptyParents(Directory directory, Directory root) async {
    var current = directory;
    final normalizedRoot = path.normalize(path.absolute(root.path));
    while (path.isWithin(
      normalizedRoot,
      path.normalize(path.absolute(current.path)),
    )) {
      if ((await current.list().toList()).isNotEmpty) {
        return;
      }
      final parent = current.parent;
      await current.delete();
      current = parent;
    }
  }

  String _randomName() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
}
