import 'package:share_plus/share_plus.dart';

abstract interface class ShareAdapter {
  Future<void> shareFile(String path);
}

final class SystemShareAdapter implements ShareAdapter {
  const SystemShareAdapter();

  @override
  Future<void> shareFile(String path) async {
    await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(path)]));
  }
}
