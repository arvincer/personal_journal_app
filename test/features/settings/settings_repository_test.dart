import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/core/database/app_database.dart';
import 'package:personal_journal_app/features/settings/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('persists export preference and user-confirmed refresh date', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);

    expect(await repository.readIncludeOriginalVideos(), isFalse);
    expect(await repository.readLastSideloadRefreshDate(), isNull);

    await repository.writeIncludeOriginalVideos(true);
    await repository.writeLastSideloadRefreshDate(DateTime(2026, 10, 10, 23));

    expect(await repository.readIncludeOriginalVideos(), isTrue);
    expect(
      await repository.readLastSideloadRefreshDate(),
      DateTime(2026, 10, 10),
    );
  });

  test('estimates seven-day free-account refresh window', () {
    expect(
      estimatedSideloadDaysRemaining(
        refreshDate: DateTime(2026, 10, 10),
        today: DateTime(2026, 10, 15, 18),
      ),
      2,
    );
    expect(
      estimatedSideloadDaysRemaining(
        refreshDate: DateTime(2026, 10, 1),
        today: DateTime(2026, 10, 15),
      ),
      0,
    );
  });
}
