import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/app/journal_app.dart';
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/core/files/app_file_store.dart';
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
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final profiles = SqliteProfileRepository(database);
    final profileController = ProfileController(profiles);
    await profileController.initialize();
    final entries = SqliteEntryRepository(database);
    final dependencies = AppDependencies(
      database: database,
      profileRepository: profiles,
      entryRepository: entries,
      mediaRepository: SqliteMediaRepository(database),
      mediaImportService: MediaImportService(
        fileStore: AppFileStore(),
        repository: SqliteMediaRepository(database),
      ),
      profileController: profileController,
      draftController: DraftController(entries),
    );
    await tester.pumpWidget(
      JournalApp.bootstrapForTest(dependencies: dependencies),
    );
    expect(find.text('今天'), findsWidgets);
    await dependencies.close();
  });
}
