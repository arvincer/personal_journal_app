import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/app/app_shell.dart';
import 'package:personal_journal_app/app/journal_app.dart';
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/core/platform/media_picker.dart';
import 'package:personal_journal_app/features/entries/draft_controller.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/entries/media_import_service.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('bootstrap pumps the journal app shell', (tester) async {
    final dependencies = (await tester.runAsync(() async {
      final database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final profiles = SqliteProfileRepository(database);
      final profileController = ProfileController(profiles);
      await profileController.initialize();
      final entries = SqliteEntryRepository(database);
      final mediaRepository = SqliteMediaRepository(database);
      final fileStore = AppFileStore();
      return AppDependencies(
        database: database,
        profileRepository: profiles,
        entryRepository: entries,
        mediaRepository: mediaRepository,
        mediaImportService: MediaImportService(
          fileStore: fileStore,
          repository: mediaRepository,
        ),
        profileController: profileController,
        draftController: DraftController(entries),
        fileStore: fileStore,
        mediaPicker: ImagePickerMediaPicker(),
      );
    }))!;

    await tester.pumpWidget(
      JournalApp.bootstrapForTest(dependencies: dependencies),
    );

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(dependencies.close);
  });
}
