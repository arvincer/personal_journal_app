import 'package:flutter/material.dart';
import 'package:personal_journal_app/core/platform/share_adapter.dart';
import 'package:personal_journal_app/features/export/analysis_export_service.dart';
import 'package:personal_journal_app/features/export/export_models.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';

typedef ExportDestinationPathProvider = Future<String> Function();
typedef ExportTodayProvider = DateTime Function();

class ExportPage extends StatefulWidget {
  const ExportPage({
    required this.profileController,
    required this.exporter,
    required this.shareAdapter,
    required this.destinationPathProvider,
    required this.appVersion,
    this.todayProvider,
    super.key,
  });

  final ProfileController profileController;
  final AnalysisExporter exporter;
  final ShareAdapter shareAdapter;
  final ExportDestinationPathProvider destinationPathProvider;
  final ExportTodayProvider? todayProvider;
  final String appVersion;

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  final Set<String> _selectedProfiles = <String>{};
  ExportRangePreset _preset = ExportRangePreset.lastSevenDays;
  DateTimeRange? _customRange;
  bool _includeOriginalVideos = false;
  bool _busy = false;
  ExportCancellationToken? _cancellationToken;
  String? _lastActiveProfileId;

  @override
  void initState() {
    super.initState();
    final activeId = widget.profileController.active?.id;
    _lastActiveProfileId = activeId;
    if (activeId != null) _selectedProfiles.add(activeId);
    widget.profileController.addListener(_handleProfileChange);
  }

  @override
  void dispose() {
    widget.profileController.removeListener(_handleProfileChange);
    super.dispose();
  }

  void _handleProfileChange() {
    final activeId = widget.profileController.active?.id;
    if (activeId == null || activeId == _lastActiveProfileId) return;
    final followsActive =
        _selectedProfiles.length == 1 &&
        _selectedProfiles.contains(_lastActiveProfileId);
    _lastActiveProfileId = activeId;
    if (followsActive && mounted) {
      setState(() {
        _selectedProfiles
          ..clear()
          ..add(activeId);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('导出')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('人物'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: widget.profileController.profiles
              .map(
                (profile) => FilterChip(
                  key: Key('export-profile-${profile.id}'),
                  label: Text(profile.name),
                  selected: _selectedProfiles.contains(profile.id),
                  onSelected: _busy
                      ? null
                      : (selected) => setState(() {
                          if (selected) {
                            _selectedProfiles.add(profile.id);
                          } else if (_selectedProfiles.length > 1) {
                            _selectedProfiles.remove(profile.id);
                          }
                        }),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ExportRangePreset>(
          initialValue: _preset,
          decoration: const InputDecoration(labelText: '日期范围'),
          items: const <DropdownMenuItem<ExportRangePreset>>[
            DropdownMenuItem(
              value: ExportRangePreset.lastSevenDays,
              child: Text('最近 7 天'),
            ),
            DropdownMenuItem(
              value: ExportRangePreset.currentMonth,
              child: Text('本月'),
            ),
            DropdownMenuItem(value: ExportRangePreset.all, child: Text('全部')),
            DropdownMenuItem(
              value: ExportRangePreset.custom,
              child: Text('自定义'),
            ),
          ],
          onChanged: _busy
              ? null
              : (value) async {
                  if (value == null) return;
                  if (value == ExportRangePreset.custom) {
                    final today = _today();
                    final selected = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: today,
                      initialDateRange: _customRange,
                    );
                    if (selected == null || !mounted) return;
                    _customRange = selected;
                  }
                  if (mounted) setState(() => _preset = value);
                },
        ),
        SwitchListTile(
          key: const Key('export-original-videos'),
          title: const Text('包含原始视频'),
          subtitle: const Text('关闭时仍包含视频缩略图、说明和时长'),
          value: _includeOriginalVideos,
          onChanged: _busy
              ? null
              : (value) => setState(() => _includeOriginalVideos = value),
        ),
        const SizedBox(height: 16),
        if (_busy) ...<Widget>[
          const LinearProgressIndicator(),
          TextButton(onPressed: _cancel, child: const Text('取消')),
        ] else ...<Widget>[
          FilledButton(
            onPressed: () => _exportAndShare(),
            child: const Text('生成并分享'),
          ),
          OutlinedButton(
            onPressed: () => _exportAndShare(),
            child: const Text('保存到文件'),
          ),
        ],
      ],
    ),
  );

  DateTime _today() {
    final value = widget.todayProvider?.call() ?? DateTime.now();
    return DateTime(value.year, value.month, value.day);
  }

  DateTimeRange _range() {
    final today = _today();
    return switch (_preset) {
      ExportRangePreset.lastSevenDays => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      ),
      ExportRangePreset.currentMonth => DateTimeRange(
        start: DateTime(today.year, today.month),
        end: today,
      ),
      ExportRangePreset.all => DateTimeRange(start: DateTime(1970), end: today),
      ExportRangePreset.custom =>
        _customRange ?? DateTimeRange(start: today, end: today),
    };
  }

  Future<void> _exportAndShare() async {
    if (_busy || _selectedProfiles.isEmpty) return;
    final token = ExportCancellationToken();
    setState(() {
      _busy = true;
      _cancellationToken = token;
    });
    try {
      final range = _range();
      final destination = await widget.destinationPathProvider();
      final file = await widget.exporter.create(
        request: AnalysisExportRequest(
          profileIds: _selectedProfiles,
          from: range.start,
          to: range.end,
          includeOriginalVideos: _includeOriginalVideos,
        ),
        profiles: widget.profileController.profiles,
        appVersion: widget.appVersion,
        destinationPath: destination,
        cancellationToken: token,
      );
      token.throwIfCancelled();
      await widget.shareAdapter.shareFile(file.path);
    } on ExportCancelledException {
      // Cancellation is user initiated and does not need an error message.
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('导出失败，请重试。')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancellationToken = null;
        });
      }
    }
  }

  void _cancel() => _cancellationToken?.cancel();
}
