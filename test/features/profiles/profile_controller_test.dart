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
