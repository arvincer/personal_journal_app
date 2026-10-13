import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/platform/share_adapter.dart';
import 'package:personal_journal_app/features/export/analysis_export_service.dart';
import 'package:personal_journal_app/features/export/export_models.dart';
import 'package:personal_journal_app/features/export/export_page.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';

void main() {
  testWidgets('exports selected profiles and shares the completed ZIP', (
    tester,
  ) async {
    final controller = await _controller();
    final exporter = _Exporter();
    final share = _Share();
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          profileController: controller,
          exporter: exporter,
          shareAdapter: share,
          destinationPathProvider: () async => 'journal.zip',
          appVersion: '1.0.0',
          todayProvider: () => DateTime(2026, 10, 13),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('export-profile-p2')));
    await tester.tap(find.byKey(const Key('export-original-videos')));
    await tester.tap(find.text('生成并分享'));
    await tester.pumpAndSettle();

    expect(exporter.request!.profileIds, <String>{'p1', 'p2'});
    expect(exporter.request!.includeOriginalVideos, isTrue);
    expect(share.paths, <String>['journal.zip']);
  });

  testWidgets('cancels an export in progress', (tester) async {
    final controller = await _controller();
    final exporter = _Exporter(block: true);
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          profileController: controller,
          exporter: exporter,
          shareAdapter: _Share(),
          destinationPathProvider: () async => 'journal.zip',
          appVersion: '1.0.0',
          todayProvider: () => DateTime(2026, 10, 13),
        ),
      ),
    );

    await tester.tap(find.text('生成并分享'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    expect(exporter.token!.isCancelled, isTrue);
    exporter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('follows the active profile until scope is customized', (
    tester,
  ) async {
    final controller = await _controller();
    final exporter = _Exporter();
    await tester.pumpWidget(
      MaterialApp(
        home: ExportPage(
          profileController: controller,
          exporter: exporter,
          shareAdapter: _Share(),
          destinationPathProvider: () async => 'journal.zip',
          appVersion: '1.0.0',
          todayProvider: () => DateTime(2026, 10, 13),
        ),
      ),
    );

    await controller.select('p2');
    await tester.pump();
    await tester.tap(find.text('生成并分享'));
    await tester.pumpAndSettle();

    expect(exporter.request!.profileIds, <String>{'p2'});
  });
}

class _Exporter implements AnalysisExporter {
  _Exporter({this.block = false});
  final bool block;
  final Completer<File> _completer = Completer<File>();
  AnalysisExportRequest? request;
  ExportCancellationToken? token;
  @override
  Future<File> create({
    required AnalysisExportRequest request,
    required List<Profile> profiles,
    required String appVersion,
    required String destinationPath,
    ExportCancellationToken? cancellationToken,
  }) {
    this.request = request;
    token = cancellationToken;
    if (block) return _completer.future;
    return Future<File>.value(File(destinationPath));
  }

  void complete() => _completer.complete(File('journal.zip'));
}

class _Share implements ShareAdapter {
  final paths = <String>[];
  @override
  Future<void> shareFile(String path) async => paths.add(path);
}

Future<ProfileController> _controller() async {
  final controller = ProfileController(_Profiles());
  await controller.initialize();
  return controller;
}

class _Profiles implements ProfileRepository {
  final profiles = <Profile>[_profile('p1', '我的日志'), _profile('p2', '孩子')];
  String? active;
  @override
  Future<Profile> ensureDefaultProfile() async => profiles.first;
  @override
  Future<List<Profile>> listActive() async => profiles;
  @override
  Future<String?> readActiveProfileId() async => active;
  @override
  Future<void> writeActiveProfileId(String id) async => active = id;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile(String id, String name) => Profile(
  id: id,
  name: name,
  avatarPath: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  isDefault: id == 'p1',
  isArchived: false,
);
