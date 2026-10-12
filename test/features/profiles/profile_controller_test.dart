import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('ProfileController', () {
    late Database database;
    late SqliteProfileRepository repository;
    late _Sequence<String> ids;
    late _Sequence<DateTime> times;

    setUp(() async {
      database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      ids = _Sequence<String>(<String>['default-id', 'child-1', 'child-2']);
      times = _Sequence<DateTime>(<DateTime>[
        DateTime.utc(2026, 10, 12),
        DateTime.utc(2026, 10, 12, 1),
        DateTime.utc(2026, 10, 12, 2),
        DateTime.utc(2026, 10, 12, 3),
        DateTime.utc(2026, 10, 12, 4),
      ]);
      repository = _repository(database, ids: ids, times: times);
    });

    tearDown(() => database.close());

    test('initialize restores a persisted active child profile', () async {
      await repository.ensureDefaultProfile();
      final child = await repository.create(name: 'Child');
      await repository.writeActiveProfileId(child.id);
      final controller = ProfileController(repository);

      await controller.initialize();

      expect(controller.active?.id, child.id);
    });

    test(
      'initialize falls back from archived or missing persisted ID',
      () async {
        final defaultProfile = await repository.ensureDefaultProfile();
        final child = await repository.create(name: 'Child');
        await repository.archive(child.id);
        await repository.writeActiveProfileId(child.id);
        final archivedController = ProfileController(repository);

        await archivedController.initialize();

        expect(archivedController.active?.id, defaultProfile.id);
        expect(await repository.readActiveProfileId(), defaultProfile.id);

        await repository.writeActiveProfileId('missing');
        final missingController = ProfileController(repository);
        await missingController.initialize();
        expect(missingController.active?.id, defaultProfile.id);
        expect(await repository.readActiveProfileId(), defaultProfile.id);
      },
    );

    test('createAndSelect creates and activates a child', () async {
      final controller = ProfileController(repository);
      await controller.initialize();

      final child = await controller.createAndSelect('  Child  ');

      expect(child.name, 'Child');
      expect(controller.active?.id, child.id);
      expect(await repository.readActiveProfileId(), child.id);
    });

    test('switching persists across controller recreation', () async {
      final controller = ProfileController(repository);
      await controller.initialize();
      final child = await controller.createAndSelect('Child');
      await controller.select('default-id');
      await controller.select(child.id);

      final recreated = ProfileController(repository);
      await recreated.initialize();

      expect(recreated.active?.id, child.id);
    });

    test('select rejects unknown IDs', () async {
      final controller = ProfileController(repository);
      await controller.initialize();

      expect(controller.select('missing'), throwsStateError);
    });

    test('archiving active child selects the default profile', () async {
      final controller = ProfileController(repository);
      await controller.initialize();
      await controller.createAndSelect('Child');

      await controller.archive(controller.active!.id);

      expect(controller.active?.id, 'default-id');
      expect(await repository.readActiveProfileId(), 'default-id');
    });

    test('archiving the last active profile is rejected', () async {
      final controller = ProfileController(repository);
      await controller.initialize();

      expect(controller.archive(controller.active!.id), throwsStateError);
      expect(controller.profiles, hasLength(1));
    });

    test(
      'profiles is unmodifiable and initialize reports loading transitions',
      () async {
        final controller = ProfileController(repository);
        final loadingStates = <bool>[];
        controller.addListener(() => loadingStates.add(controller.loading));

        await controller.initialize();

        expect(loadingStates, <bool>[true, false]);
        expect(controller.loading, isFalse);
        expect(
          () => controller.profiles.add(
            Profile(
              id: 'external',
              name: 'External',
              avatarPath: null,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              isDefault: false,
              isArchived: false,
            ),
          ),
          throwsUnsupportedError,
        );
      },
    );

    test('renaming reloads profiles and preserves active selection', () async {
      final controller = ProfileController(repository);
      await controller.initialize();
      final child = await controller.createAndSelect('Child');

      await controller.rename(child.id, 'Renamed');

      expect(controller.active?.id, child.id);
      expect(controller.active?.name, 'Renamed');
    });

    test('rename rejects unknown IDs before calling the repository', () async {
      final recordingRepository = _RenameRecordingRepository(repository);
      final controller = ProfileController(recordingRepository);
      await controller.initialize();

      expect(controller.rename('missing', 'Name'), throwsStateError);
      expect(recordingRepository.renameCalls, 0);
    });

    test('rename rejects archived IDs before calling the repository', () async {
      await repository.ensureDefaultProfile();
      final child = await repository.create(name: 'Child');
      await repository.archive(child.id);
      final recordingRepository = _RenameRecordingRepository(repository);
      final controller = ProfileController(recordingRepository);
      await controller.initialize();

      expect(controller.rename(child.id, 'Name'), throwsStateError);
      expect(recordingRepository.renameCalls, 0);
    });

    test('initialize completion after dispose does not notify', () async {
      final delayedRepository = _DelayedEnsureRepository(repository);
      final controller = ProfileController(delayedRepository);
      var listenerCalls = 0;
      controller.addListener(() => listenerCalls++);

      final initialization = controller.initialize();
      expect(listenerCalls, 1);
      controller.dispose();
      delayedRepository.releaseEnsure();

      await expectLater(initialization, completes);
      expect(listenerCalls, 1);
    });

    test('rename and archive cannot overwrite state out of order', () async {
      final delayedRepository = _DelayedMutationRepository(repository);
      final controller = ProfileController(delayedRepository);
      await controller.initialize();
      final child = await controller.createAndSelect('Child');
      delayedRepository.delayRename(child.id);

      final rename = controller.rename(child.id, 'Renamed');
      await delayedRepository.renameStarted;
      final archive = controller.archive(child.id);
      await Future<void>.delayed(Duration.zero);
      final archiveCallsBeforeRelease = delayedRepository.archiveCalls;
      delayedRepository.releaseRename();
      await Future.wait(<Future<void>>[rename, archive]);

      expect(archiveCallsBeforeRelease, 0);
      expect(controller.active?.id, 'default-id');
      expect(controller.profiles.map((profile) => profile.id), <String>[
        'default-id',
      ]);
    });

    test('select and archive cannot persist an archived profile', () async {
      final delayedRepository = _DelayedMutationRepository(repository);
      final controller = ProfileController(delayedRepository);
      await controller.initialize();
      final child = await controller.createAndSelect('Child');
      await controller.select('default-id');
      delayedRepository.delayActiveWrite(child.id);

      final select = controller.select(child.id);
      await delayedRepository.activeWriteStarted;
      final archive = controller.archive(child.id);
      await Future<void>.delayed(Duration.zero);
      delayedRepository.releaseActiveWrite();
      await Future.wait(<Future<void>>[select, archive]);

      expect(controller.active?.id, 'default-id');
      expect(await repository.readActiveProfileId(), 'default-id');
      expect(controller.profiles.map((profile) => profile.id), <String>[
        'default-id',
      ]);
    });

    test(
      'close drains a pending mutation and rejects new operations',
      () async {
        final delayedRepository = _DelayedMutationRepository(repository);
        final controller = ProfileController(delayedRepository);
        await controller.initialize();
        final child = await controller.createAndSelect('Child');
        await controller.select('default-id');
        delayedRepository.delayActiveWrite(child.id);

        final selection = controller.select(child.id);
        await delayedRepository.activeWriteStarted;
        var closeCompleted = false;
        final close = controller.close().then((_) => closeCompleted = true);
        await Future<void>.delayed(Duration.zero);

        expect(closeCompleted, isFalse);
        await expectLater(
          controller.select('default-id'),
          throwsA(isA<StateError>()),
        );

        delayedRepository.releaseActiveWrite();
        await selection;
        await close;
        expect(closeCompleted, isTrue);
      },
    );

    test('archiving a nonactive profile preserves active selection', () async {
      final controller = ProfileController(repository);
      await controller.initialize();
      final child = await controller.createAndSelect('Child');
      await controller.select('default-id');

      await controller.archive(child.id);

      expect(controller.active?.id, 'default-id');
    });
  });
}

SqliteProfileRepository _repository(
  Database database, {
  required _Sequence<String> ids,
  required _Sequence<DateTime> times,
}) {
  return SqliteProfileRepository(
    database,
    idProvider: ids.next,
    nowProvider: times.next,
  );
}

final class _Sequence<T> {
  _Sequence(this._values);

  final List<T> _values;
  int _index = 0;

  T next() => _values[_index++];
}

final class _RenameRecordingRepository implements ProfileRepository {
  _RenameRecordingRepository(this._delegate);

  final ProfileRepository _delegate;
  int renameCalls = 0;

  @override
  Future<void> archive(String id) => _delegate.archive(id);

  @override
  Future<Profile> create({required String name}) =>
      _delegate.create(name: name);

  @override
  Future<Profile> ensureDefaultProfile() => _delegate.ensureDefaultProfile();

  @override
  Future<List<Profile>> listActive() => _delegate.listActive();

  @override
  Future<String?> readActiveProfileId() => _delegate.readActiveProfileId();

  @override
  Future<void> rename({required String id, required String name}) {
    renameCalls++;
    return _delegate.rename(id: id, name: name);
  }

  @override
  Future<void> writeActiveProfileId(String id) =>
      _delegate.writeActiveProfileId(id);
}

final class _DelayedEnsureRepository implements ProfileRepository {
  _DelayedEnsureRepository(this._delegate);

  final ProfileRepository _delegate;
  final _ensureRelease = Completer<void>();

  void releaseEnsure() => _ensureRelease.complete();

  @override
  Future<void> archive(String id) => _delegate.archive(id);

  @override
  Future<Profile> create({required String name}) =>
      _delegate.create(name: name);

  @override
  Future<Profile> ensureDefaultProfile() async {
    await _ensureRelease.future;
    return _delegate.ensureDefaultProfile();
  }

  @override
  Future<List<Profile>> listActive() => _delegate.listActive();

  @override
  Future<String?> readActiveProfileId() => _delegate.readActiveProfileId();

  @override
  Future<void> rename({required String id, required String name}) =>
      _delegate.rename(id: id, name: name);

  @override
  Future<void> writeActiveProfileId(String id) =>
      _delegate.writeActiveProfileId(id);
}

final class _DelayedMutationRepository implements ProfileRepository {
  _DelayedMutationRepository(this._delegate);

  final ProfileRepository _delegate;
  String? _delayedRenameId;
  String? _delayedActiveWriteId;
  Completer<void>? _renameStarted;
  Completer<void>? _renameRelease;
  Completer<void>? _activeWriteStarted;
  Completer<void>? _activeWriteRelease;
  int archiveCalls = 0;

  Future<void> get renameStarted => _renameStarted!.future;
  Future<void> get activeWriteStarted => _activeWriteStarted!.future;

  void delayRename(String id) {
    _delayedRenameId = id;
    _renameStarted = Completer<void>();
    _renameRelease = Completer<void>();
  }

  void releaseRename() => _renameRelease!.complete();

  void delayActiveWrite(String id) {
    _delayedActiveWriteId = id;
    _activeWriteStarted = Completer<void>();
    _activeWriteRelease = Completer<void>();
  }

  void releaseActiveWrite() => _activeWriteRelease!.complete();

  @override
  Future<void> archive(String id) {
    archiveCalls++;
    return _delegate.archive(id);
  }

  @override
  Future<Profile> create({required String name}) =>
      _delegate.create(name: name);

  @override
  Future<Profile> ensureDefaultProfile() => _delegate.ensureDefaultProfile();

  @override
  Future<List<Profile>> listActive() => _delegate.listActive();

  @override
  Future<String?> readActiveProfileId() => _delegate.readActiveProfileId();

  @override
  Future<void> rename({required String id, required String name}) async {
    if (id == _delayedRenameId) {
      _renameStarted!.complete();
      await _renameRelease!.future;
    }
    await _delegate.rename(id: id, name: name);
  }

  @override
  Future<void> writeActiveProfileId(String id) async {
    if (id == _delayedActiveWriteId) {
      _activeWriteStarted!.complete();
      await _activeWriteRelease!.future;
    }
    await _delegate.writeActiveProfileId(id);
  }
}
