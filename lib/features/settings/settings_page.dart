import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:personal_journal_app/features/backup/restore_preview.dart';
import 'package:personal_journal_app/features/backup/restore_service.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_switcher.dart';
import 'package:personal_journal_app/features/settings/settings_repository.dart';
import 'package:personal_journal_app/features/settings/storage_stats_service.dart';

typedef BackupFilePicker = Future<String?> Function();
typedef RestoreRefresh = Future<void> Function();
typedef CreateBackupAction = Future<void> Function();
typedef SettingsTodayProvider = DateTime Function();

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.restorer,
    required this.onRestored,
    this.backupFilePicker = pickBackupZip,
    this.profileController,
    this.settingsRepository,
    this.storageStatsLoader,
    this.createBackup,
    this.todayProvider,
    super.key,
  });

  final BackupRestorer restorer;
  final RestoreRefresh onRestored;
  final BackupFilePicker backupFilePicker;
  final ProfileController? profileController;
  final SettingsRepository? settingsRepository;
  final StorageStatsLoader? storageStatsLoader;
  final CreateBackupAction? createBackup;
  final SettingsTodayProvider? todayProvider;

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
  var _includeOriginalVideos = false;
  DateTime? _lastRefreshDate;
  StorageStats? _storageStats;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final repository = widget.settingsRepository;
    final loader = widget.storageStatsLoader;
    final includeOriginalVideos = repository == null
        ? false
        : await repository.readIncludeOriginalVideos();
    final lastRefreshDate = repository == null
        ? null
        : await repository.readLastSideloadRefreshDate();
    final storageStats = loader == null ? null : await loader.scan();
    if (!mounted) return;
    setState(() {
      _includeOriginalVideos = includeOriginalVideos;
      _lastRefreshDate = lastRefreshDate;
      _storageStats = storageStats;
    });
  }

  Future<void> _setIncludeOriginalVideos(bool value) async {
    await widget.settingsRepository?.writeIncludeOriginalVideos(value);
    if (mounted) setState(() => _includeOriginalVideos = value);
  }

  Future<void> _confirmRefreshToday() async {
    final now = widget.todayProvider?.call() ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await widget.settingsRepository?.writeLastSideloadRefreshDate(today);
    if (mounted) setState(() => _lastRefreshDate = today);
  }

  Future<void> _createBackup() async {
    final action = widget.createBackup;
    if (_busy || action == null) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('备份失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameProfile(String id, String currentName) async {
    if (_busy) return;
    final textController = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改用户名称'),
        content: TextField(controller: textController, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    await _runProfileAction(() => widget.profileController!.rename(id, name));
  }

  Future<void> _archiveProfile(String id, String name) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('归档用户'),
        content: Text('确认归档“$name”？日志不会被删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runProfileAction(() => widget.profileController!.archive(id));
    }
  }

  Future<void> _runProfileAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('用户操作失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
  Widget build(BuildContext context) {
    final refreshDate = _lastRefreshDate;
    final daysRemaining = refreshDate == null
        ? null
        : estimatedSideloadDaysRemaining(
            refreshDate: refreshDate,
            today: widget.todayProvider?.call() ?? DateTime.now(),
          );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('设置', style: TextStyle(fontSize: 24)),
          const SizedBox(height: 16),
          if (widget.profileController case final controller?) ...<Widget>[
            const Text('用户'),
            ProfileSwitcher(controller: controller),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Column(
                children: controller.profiles
                    .map(
                      (profile) => ListTile(
                        dense: true,
                        title: Text(profile.name),
                        subtitle: profile.id == controller.active?.id
                            ? const Text('当前用户')
                            : null,
                        trailing: Wrap(
                          children: <Widget>[
                            IconButton(
                              key: Key('rename-profile-${profile.id}'),
                              tooltip: '修改名称',
                              onPressed: _busy
                                  ? null
                                  : () => _renameProfile(
                                      profile.id,
                                      profile.name,
                                    ),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              key: Key('archive-profile-${profile.id}'),
                              tooltip: '归档',
                              onPressed:
                                  _busy || controller.profiles.length == 1
                                  ? null
                                  : () => _archiveProfile(
                                      profile.id,
                                      profile.name,
                                    ),
                              icon: const Icon(Icons.archive_outlined),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const Divider(),
          ],
          if (_storageStats case final stats?) ...<Widget>[
            const Text('存储占用'),
            Text('数据库 ${_formatBytes(stats.databaseBytes)}'),
            Text('图片 ${_formatBytes(stats.imageBytes)}'),
            Text('视频 ${_formatBytes(stats.videoBytes)}'),
            Text('缩略图 ${_formatBytes(stats.thumbnailBytes)}'),
            Text('临时文件 ${_formatBytes(stats.temporaryBytes)}'),
            Text('合计 ${_formatBytes(stats.totalBytes)}'),
            const Divider(),
          ],
          if (widget.settingsRepository != null)
            SwitchListTile(
              key: const Key('default-original-videos'),
              title: const Text('分析包默认包含原始视频'),
              value: _includeOriginalVideos,
              onChanged: _busy ? null : _setIncludeOriginalVideos,
            ),
          if (widget.createBackup != null)
            ListTile(
              key: const Key('create-full-backup'),
              leading: const Icon(Icons.backup_outlined),
              title: const Text('创建完整备份'),
              subtitle: const Text('建议在刷新侧载前先备份'),
              enabled: !_busy,
              onTap: _createBackup,
            ),
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
          const Divider(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('免费侧载提醒'),
                  const SizedBox(height: 8),
                  Text(
                    daysRemaining == null
                        ? '尚未记录最近刷新日期。此处无法读取 Apple 的真实签名状态。'
                        : '预计剩余 $daysRemaining 天（基于你确认的刷新日期，并非 Apple 实时状态）',
                    key: const Key('sideload-estimate'),
                  ),
                  if (daysRemaining != null && daysRemaining <= 2) ...<Widget>[
                    const SizedBox(height: 8),
                    const Text('建议立即备份，并尽快刷新侧载。'),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('confirm-sideload-refresh'),
                    onPressed: _confirmRefreshToday,
                    child: const Text('我刚刚完成刷新'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
