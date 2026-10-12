import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app/journal_app.dart';
import 'core/database/app_database.dart';
import 'core/files/app_file_store.dart';
import 'core/platform/media_picker.dart';
import 'features/entries/draft_controller.dart';
import 'features/entries/entry_repository.dart';
import 'features/entries/media_import_service.dart';
import 'features/entries/media_repository.dart';
import 'features/profiles/profile_controller.dart';
import 'features/profiles/profile_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Database? database;
  try {
    final support = await getApplicationSupportDirectory();
    database = await AppDatabase.open(
      path: path.join(support.path, 'journal.db'),
    );
    final profileRepository = SqliteProfileRepository(database);
    final entryRepository = SqliteEntryRepository(database);
    final mediaRepository = SqliteMediaRepository(database);
    final fileStore = AppFileStore();
    final profileController = ProfileController(profileRepository);
    await profileController.initialize();
    final dependencies = AppDependencies(
      database: database,
      profileRepository: profileRepository,
      entryRepository: entryRepository,
      mediaRepository: mediaRepository,
      mediaImportService: MediaImportService(
        fileStore: fileStore,
        repository: mediaRepository,
        thumbnailGenerator: PlatformVideoThumbnailGenerator(),
      ),
      profileController: profileController,
      draftController: DraftController(entryRepository),
      fileStore: fileStore,
      mediaPicker: ImagePickerMediaPicker(),
    );
    runApp(JournalApp(dependencies: dependencies, ownsDependencies: true));
  } catch (_) {
    await database?.close();
    runApp(const StartupErrorApp());
  }
}
