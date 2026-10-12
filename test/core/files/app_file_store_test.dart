import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/files/checksum_service.dart';

void main() {
  group('AppFileStore', () {
    late Directory sandbox;
    late Directory support;
    late Directory temporary;
    late AppFileStore store;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('journal-file-store-');
      support = Directory('${sandbox.path}${Platform.pathSeparator}support');
      temporary = Directory(
        '${sandbox.path}${Platform.pathSeparator}temporary',
      );
      store = AppFileStore(
        supportDirectoryProvider: () async => support,
        temporaryDirectoryProvider: () async => temporary,
      );
    });

    tearDown(() => sandbox.delete(recursive: true));

    test('stages and commits jpg bytes under the private image path', () async {
      final source = File('${sandbox.path}${Platform.pathSeparator}photo.JPG');
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      await source.writeAsBytes(bytes);

      final staged = await store.stageCopy(source.path);
      final relative = await store.commitImage(staged, 'm1', '.JPG');

      expect(relative, 'media/images/m1.jpg');
      expect(await (await store.resolve(relative)).readAsBytes(), bytes);
      expect(await staged.exists(), isTrue);
    });

    test('rejects path traversal and unsafe media identifiers', () async {
      final source = File('${sandbox.path}${Platform.pathSeparator}photo.jpg');
      await source.writeAsBytes(<int>[1]);
      final staged = await store.stageCopy(source.path);

      await expectLater(store.resolve('../escape.jpg'), throwsArgumentError);
      await expectLater(store.resolve(sandbox.path), throwsArgumentError);
      await expectLater(
        store.commitImage(staged, '../m1', 'jpg'),
        throwsArgumentError,
      );
      await expectLater(
        store.deleteRelative('../escape.jpg'),
        throwsArgumentError,
      );
    });
  });

  test('SHA-256 checksum hashes UTF-8 abc', () async {
    final checksum = await Sha256ChecksumService().forBytes(
      Uint8List.fromList('abc'.codeUnits),
    );

    expect(
      checksum,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}
