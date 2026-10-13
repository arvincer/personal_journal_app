import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app/journal_app.dart';
import 'core/database/app_database.dart';
import 'core/files/app_file_store.dart';
import 'core/files/checksum_service.dart';
import 'core/files/zip_service.dart';
import 'core/platform/media_picker.dart';
import 'core/platform/share_adapter.dart';
import 'features/entries/draft_controller.dart';
import 'features/backup/restore_service.dart';
import 'features/backup/backup_service.dart';
import 'features/entries/entry_repository.dart';
import 'features/entries/media_import_service.dart';
import 'features/entries/media_repository.dart';
import 'features/export/analysis_export_service.dart';
import 'features/export/markdown_renderer.dart';
import 'features/profiles/profile_controller.dart';
import 'features/profiles/profile_repository.dart';
import 'features/settings/settings_repository.dart';
import 'features/settings/storage_stats_service.dart';

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
    final settingsRepository = SqliteSettingsRepository(database);
    final storageStatsLoader = StorageStatsService(
      supportDirectoryProvider: getApplicationSupportDirectory,
      temporaryDirectoryProvider: getTemporaryDirectory,
    );
    final shareAdapter = const SystemShareAdapter();
    final backupService = BackupService(
      database: database,
      snapshotFactory: databaseFactory,
      fileStore: fileStore,
      checksumService: Sha256ChecksumService(),
      zipService: const ZipService(),
      temporaryDirectoryProvider: getTemporaryDirectory,
    );
    final initialIncludeOriginalVideos = await settingsRepository
        .readIncludeOriginalVideos();
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
      analysisExporter: AnalysisExportService(
        entryRepository: entryRepository,
        mediaRepository: mediaRepository,
        fileStore: fileStore,
        zipService: const ZipService(),
        markdownRenderer: MarkdownRenderer(),
        temporaryDirectoryProvider: getTemporaryDirectory,
      ),
      shareAdapter: shareAdapter,
      exportDestinationPathProvider: () async {
        final temporary = await getTemporaryDirectory();
        final exports = Directory(path.join(temporary.path, 'exports'));
        await exports.create(recursive: true);
        return path.join(
          exports.path,
          'PersonalJournal-${DateTime.now().millisecondsSinceEpoch}.zip',
        );
      },
      restoreService: RestoreService(
        database: database,
        snapshotFactory: databaseFactory,
        fileStore: fileStore,
        checksumService: Sha256ChecksumService(),
        temporaryDirectoryProvider: getTemporaryDirectory,
      ),
      settingsRepository: settingsRepository,
      storageStatsLoader: storageStatsLoader,
      initialIncludeOriginalVideos: initialIncludeOriginalVideos,
      createBackup: () async {
        final temporary = await getTemporaryDirectory();
        final backups = Directory(path.join(temporary.path, 'backups'));
        await backups.create(recursive: true);
        final backup = await backupService.createFullBackup(
          destinationPath: path.join(
            backups.path,
            'PersonalJournal-Backup-${DateTime.now().millisecondsSinceEpoch}.zip',
          ),
          appVersion: '1.0.0',
        );
        await shareAdapter.shareFile(backup.path);
      },
    );
    runApp(JournalApp(dependencies: dependencies, ownsDependencies: true));
  } catch (_) {
    await database?.close();
    runApp(const StartupErrorApp());
  }
}
