import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:personal_journal_app/features/backup/restore_preview.dart';
import 'package:personal_journal_app/features/backup/restore_service.dart';

typedef BackupFilePicker = Future<String?> Function();
typedef RestoreRefresh = Future<void> Function();

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.restorer,
    required this.onRestored,
    this.backupFilePicker = pickBackupZip,
    super.key,
  });

  final BackupRestorer restorer;
  final RestoreRefresh onRestored;
  final BackupFilePicker backupFilePicker;

  static Future<String?> pickBackupZip() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    return result?.path;
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  var _busy = false;

  Future<void> _chooseAndRestore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final archivePath = await widget.backupFilePicker();
      if (archivePath == null || !mounted) return;
      final preview = await widget.restorer.preview(archivePath);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认恢复备份'),
          content: _RestorePreviewSummary(preview: preview),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('confirm-restore'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final report = await widget.restorer.restore(archivePath);
      await widget.onRestored();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '恢复完成：${report.insertedProfiles} 个用户、'
            '${report.insertedEntries} 条日志、${report.insertedMedia} 个媒体文件',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('设置', style: TextStyle(fontSize: 24)),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('从完整备份恢复'),
          subtitle: const Text('校验后合并，已有相同记录不会被覆盖'),
          trailing: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          enabled: !_busy,
          onTap: _chooseAndRestore,
        ),
      ],
    ),
  );
}

class _RestorePreviewSummary extends StatelessWidget {
  const _RestorePreviewSummary({required this.preview});

  final RestorePreview preview;

  @override
  Widget build(BuildContext context) => Text(
    '将新增 ${preview.newProfiles} 个用户、${preview.newEntries} 条日志、'
    '${preview.newMedia} 个媒体文件。\n'
    '将跳过 ${preview.duplicateProfiles} 个重复用户、'
    '${preview.duplicateEntries} 条重复日志、'
    '${preview.duplicateMedia} 个重复媒体文件。',
  );
}
