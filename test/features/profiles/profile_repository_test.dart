import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('SqliteProfileRepository', () {
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

    test('ensureDefaultProfile creates one default profile only', () async {
      final first = await repository.ensureDefaultProfile();
      final second = await repository.ensureDefaultProfile();
      final rows = await database.query('profiles');

      expect(first.id, 'default-id');
      expect(second.id, first.id);
      expect(first.name, '我的日志');
      expect(first.isDefault, isTrue);
      expect(rows, hasLength(1));
    });

    test('ensureDefaultProfile coalesces concurrent creation', () async {
      final profiles = await Future.wait(<Future<Profile>>[
        repository.ensureDefaultProfile(),
        repository.ensureDefaultProfile(),
        repository.ensureDefaultProfile(),
      ]);

      expect(profiles.map((profile) => profile.id).toSet(), {'default-id'});
      expect(await database.query('profiles'), hasLength(1));
    });

    test(
      'ensureDefaultProfile creates one default beside non-default profiles',
      () async {
        final child = await repository.create(name: 'Child');

        final defaults = await Future.wait(<Future<Profile>>[
          repository.ensureDefaultProfile(),
          repository.ensureDefaultProfile(),
        ]);

        expect(defaults.map((profile) => profile.id).toSet(), <String>{
          'child-1',
        });
        expect(defaults.first.name, '我的日志');
        expect(defaults.first.isDefault, isTrue);
        expect(
          (await repository.listActive()).map((profile) => profile.id),
          <String>[defaults.first.id, child.id],
        );
      },
    );

    test('ensureDefaultProfile replaces an all-archived profile set', () async {
      final archived = await repository.create(name: 'Archived');
      await repository.archive(archived.id);

      final createdDefault = await repository.ensureDefaultProfile();

      expect(createdDefault.id, 'child-1');
      expect(createdDefault.name, '我的日志');
      expect(createdDefault.isDefault, isTrue);
      expect(createdDefault.isArchived, isFalse);
      expect(
        (await repository.listActive()).map((profile) => profile.id),
        <String>[createdDefault.id],
      );
    });

    test(
      'listActive puts default first and excludes archived profiles',
      () async {
        final defaultProfile = await repository.ensureDefaultProfile();
        final firstChild = await repository.create(name: 'First');
        final secondChild = await repository.create(name: 'Second');
        await repository.archive(firstChild.id);

        final active = await repository.listActive();

        expect(active.map((profile) => profile.id), <String>[
          defaultProfile.id,
          secondChild.id,
        ]);
      },
    );

    test('create and rename trim names', () async {
      final profile = await repository.create(name: '  Child  ');
      await repository.rename(id: profile.id, name: '  Renamed  ');

      final active = await repository.listActive();

      expect(active.single.name, 'Renamed');
      expect(active.single.updatedAt, DateTime.utc(2026, 10, 12, 1));
    });

    test('create and rename reject blank names', () async {
      expect(repository.create(name: '   '), throwsArgumentError);
      expect(
        repository.rename(id: 'missing', name: '\n\t'),
        throwsArgumentError,
      );
    });

    test('rename and archive reject unknown IDs', () async {
      expect(repository.rename(id: 'missing', name: 'Name'), throwsStateError);
      expect(repository.archive('missing'), throwsStateError);
    });

    test('archive keeps entries belonging to the profile', () async {
      final profile = await repository.create(name: 'Child');
      await database.insert('entries', <String, Object?>{
        'id': 'entry-1',
        'profile_id': profile.id,
        'text': 'Kept',
        'created_at': '2026-10-12T00:00:00.000Z',
        'updated_at': '2026-10-12T00:00:00.000Z',
        'local_date': '2026-10-12',
        'timezone_offset_minutes': 0,
        'status': 'published',
      });

      await repository.archive(profile.id);

      expect(await repository.listActive(), isEmpty);
      expect(await database.query('entries'), hasLength(1));
      final row = (await database.query(
        'profiles',
        where: 'id = ?',
        whereArgs: <Object?>[profile.id],
      )).single;
      expect(row['is_archived'], 1);
    });

    test('active profile ID survives a repository recreation', () async {
      expect(await repository.readActiveProfileId(), isNull);
      await repository.writeActiveProfileId('child-1');

      final recreated = _repository(database, ids: ids, times: times);

      expect(await recreated.readActiveProfileId(), 'child-1');
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
