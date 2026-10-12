import 'dart:async';

import 'package:flutter/material.dart';
import 'package:personal_journal_app/app/app_shell.dart';
import 'package:personal_journal_app/features/entries/draft_controller.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/entries/media_import_service.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';
import 'package:sqflite/sqflite.dart';

class AppDependencies {
  AppDependencies({
    required this.database,
    required this.profileRepository,
    required this.entryRepository,
    required this.mediaRepository,
    required this.mediaImportService,
    required this.profileController,
    required this.draftController,
  });
  final Database database;
  final ProfileRepository profileRepository;
  final EntryRepository entryRepository;
  final MediaRepository mediaRepository;
  final MediaImportService mediaImportService;
  final ProfileController profileController;
  final DraftController draftController;
  Future<void>? _closeFuture;
  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    await draftController.close();
    await profileController.close();
    await database.close();
  }
}

class JournalApp extends StatefulWidget {
  const JournalApp({
    required this.dependencies,
    this.ownsDependencies = false,
    super.key,
  });
  final AppDependencies dependencies;
  final bool ownsDependencies;
  static Widget bootstrapForTest({required AppDependencies dependencies}) =>
      JournalApp(dependencies: dependencies);
  @override
  State<JournalApp> createState() => _JournalAppState();
}

class _JournalAppState extends State<JournalApp> {
  @override
  void dispose() {
    if (widget.ownsDependencies) unawaited(widget.dependencies.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: AppShell(profileController: widget.dependencies.profileController),
  );
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('应用启动失败，请关闭后重试。', textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}
