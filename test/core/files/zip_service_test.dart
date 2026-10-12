import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:personal_journal_app/core/files/zip_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('journal-zip-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('creates a ZIP with portable relative entry names', () async {
    final staging = Directory(path.join(root.path, 'staging'));
    await Directory(path.join(staging.path, 'days')).create(recursive: true);
    await File(path.join(staging.path, 'README.md')).writeAsString('readme');
    await File(path.join(staging.path, 'days', '2026-10-12.md'))
        .writeAsString('day');
    final destination = path.join(root.path, 'journal.zip');

    final result = await const ZipService().create(
      stagingDirectory: staging,
      destinationPath: destination,
    );

    expect(result.path, destination);
    final archive = ZipDecoder().decodeBytes(await result.readAsBytes());
    expect(
      archive.files.where((file) => file.isFile).map((file) => file.name),
      containsAll(<String>['README.md', 'days/2026-10-12.md']),
    );
    expect(await File('$destination.part').exists(), isFalse);
  });

  test('refuses to publish over an existing archive', () async {
    final staging = Directory(path.join(root.path, 'staging'));
    await staging.create();
    await File(path.join(staging.path, 'README.md')).writeAsString('new');
    final destination = File(path.join(root.path, 'journal.zip'));
    await destination.writeAsString('existing');

    await expectLater(
      const ZipService().create(
        stagingDirectory: staging,
        destinationPath: destination.path,
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(await destination.readAsString(), 'existing');
    expect(await File('${destination.path}.part').exists(), isFalse);
  });

  test('rejects a destination inside the staging directory', () async {
    final staging = Directory(path.join(root.path, 'staging'));
    await staging.create();

    await expectLater(
      const ZipService().create(
        stagingDirectory: staging,
        destinationPath: path.join(staging.path, 'journal.zip'),
      ),
      throwsArgumentError,
    );
  });
}
