import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract interface class ChecksumService {
  Future<String> forBytes(Uint8List bytes);
  Future<String> forFile(String path);
}

final class Sha256ChecksumService implements ChecksumService {
  @override
  Future<String> forBytes(Uint8List bytes) async =>
      sha256.convert(bytes).toString();

  @override
  Future<String> forFile(String path) async =>
      forBytes(await File(path).readAsBytes());
}
