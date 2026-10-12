import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app/journal_app.dart';
import 'core/database/app_database.dart';
import 'core/files/app_file_store.dart';
import 'features/entries/draft_controller.dart';
import 'features/entries/entry_repository.dart';
import 'features/entries/media_import_service.dart';
import 'features/entries/media_repository.dart';
import 'features/profiles/profile_controller.dart';
import 'features/profiles/profile_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final database = await AppDatabase.open(
    path: path.join(support.path, 'journal.db'),
  );
  final profileRepository = SqliteProfileRepository(database);
  final entryRepository = SqliteEntryRepository(database);
  final mediaRepository = SqliteMediaRepository(database);
  final profileController = ProfileController(profileRepository);
  await profileController.initialize();
  final draftController = DraftController(entryRepository);
  final mediaImportService = MediaImportService(
    fileStore: AppFileStore(),
    repository: mediaRepository,
  );
  runApp(
    JournalApp(
      dependencies: AppDependencies(
        profileRepository: profileRepository,
        entryRepository: entryRepository,
        mediaRepository: mediaRepository,
        mediaImportService: mediaImportService,
        profileController: profileController,
        draftController: draftController,
      ),
    ),
  );
}
