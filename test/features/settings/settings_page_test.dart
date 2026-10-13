import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/features/backup/restore_preview.dart';
import 'package:personal_journal_app/features/backup/restore_service.dart';
import 'package:personal_journal_app/features/settings/settings_page.dart';

void main() {
  testWidgets('previews and confirms a selected backup before restoring', (
    tester,
  ) async {
    final restorer = _FakeRestorer();
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            restorer: restorer,
            backupFilePicker: () async => 'backup.zip',
            onRestored: () async => refreshes++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('从完整备份恢复'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(restorer.previewedPath, 'backup.zip');
    expect(find.textContaining('将新增 1 个用户'), findsOneWidget);
    expect(restorer.restoredPath, isNull);

    await tester.tap(find.byKey(const Key('confirm-restore')));
    await tester.pumpAndSettle();
    expect(restorer.restoredPath, 'backup.zip');
    expect(refreshes, 1);
    expect(find.textContaining('恢复完成'), findsOneWidget);
  });
}

final class _FakeRestorer implements BackupRestorer {
  String? previewedPath;
  String? restoredPath;

  @override
  Future<RestorePreview> preview(String archivePath) async {
    previewedPath = archivePath;
    return const RestorePreview(
      newProfiles: 1,
      duplicateProfiles: 0,
      newEntries: 2,
      duplicateEntries: 0,
      newMedia: 3,
      duplicateMedia: 0,
      missingFiles: 0,
      damagedFiles: 0,
    );
  }

  @override
  Future<RestoreReport> restore(String archivePath) async {
    restoredPath = archivePath;
    return const RestoreReport(
      insertedProfiles: 1,
      insertedEntries: 2,
      insertedMedia: 3,
    );
  }
}
