import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

final class ZipService {
  const ZipService();

  Future<File> create({
    required Directory stagingDirectory,
    required String destinationPath,
  }) async {
    if (!await stagingDirectory.exists()) {
      throw ArgumentError.value(
        stagingDirectory.path,
        'stagingDirectory',
        'Directory does not exist.',
      );
    }
    final stagingRoot = path.normalize(
      await stagingDirectory.resolveSymbolicLinks(),
    );
    final destination = File(path.normalize(path.absolute(destinationPath)));
    if (path.equals(stagingRoot, destination.path) ||
        path.isWithin(stagingRoot, destination.path)) {
      throw ArgumentError.value(
        destinationPath,
        'destinationPath',
        'Destination must be outside staging.',
      );
    }
    if (await destination.exists()) {
      throw FileSystemException(
        'Refusing to overwrite an existing archive.',
        destination.path,
      );
    }

    await _validateTree(Directory(stagingRoot));
    await destination.parent.create(recursive: true);
    final temporary = File(
      '${destination.path}.part-${DateTime.now().microsecondsSinceEpoch}-$pid',
    );
    try {
      await ZipFileEncoder().zipDirectory(
        Directory(stagingRoot),
        filename: temporary.path,
        followLinks: false,
      );
      if (await destination.exists()) {
        throw FileSystemException(
          'Archive appeared while export was running.',
          destination.path,
        );
      }
      return await temporary.rename(destination.path);
    } catch (error, stackTrace) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Preserve the primary archive error.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _validateTree(Directory root) async {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final normalized = path.normalize(path.absolute(entity.path));
      if (!path.isWithin(root.path, normalized)) {
        throw FileSystemException('ZIP entry escapes staging.', entity.path);
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FileSystemException('ZIP entries cannot be links.', entity.path);
      }
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.directory) {
        throw FileSystemException('Unsupported ZIP entry type.', entity.path);
      }
    }
  }
}
