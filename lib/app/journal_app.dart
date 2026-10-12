import 'package:flutter/material.dart';
import 'package:personal_journal_app/app/app_shell.dart';
import 'package:personal_journal_app/features/entries/draft_controller.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/entries/media_import_service.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';

class AppDependencies {
  const AppDependencies({
    required this.profileRepository,
    required this.entryRepository,
    required this.mediaRepository,
    required this.mediaImportService,
    required this.profileController,
    required this.draftController,
  });
  final ProfileRepository profileRepository;
  final EntryRepository entryRepository;
  final MediaRepository mediaRepository;
  final MediaImportService mediaImportService;
  final ProfileController profileController;
  final DraftController draftController;
}

class JournalApp extends StatelessWidget {
  const JournalApp({required this.dependencies, super.key});
  final AppDependencies dependencies;
  static Widget bootstrapForTest({required AppDependencies dependencies}) =>
      JournalApp(dependencies: dependencies);
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: AppShell(profileController: dependencies.profileController),
  );
}
