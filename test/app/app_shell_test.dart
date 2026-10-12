import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/app/app_shell.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';

void main() {
  testWidgets(
    'shows four destinations and keeps today state while navigating',
    (tester) async {
      final controller = await _controller();
      await tester.pumpWidget(
        MaterialApp(home: AppShell(profileController: controller)),
      );

      expect(find.text('今天'), findsWidgets);
      expect(find.text('日历'), findsWidgets);
      expect(find.text('导出'), findsWidgets);
      expect(find.text('设置'), findsWidgets);
      await tester.enterText(
        find.byKey(const Key('today-draft-input')),
        'kept',
      );
      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      expect(find.text('kept'), findsOneWidget);
    },
  );

  testWidgets('export receives the active profile scope', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(
      MaterialApp(home: AppShell(profileController: controller)),
    );
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('export-profile-scope-default')),
      findsOneWidget,
    );
  });
}

Future<ProfileController> _controller() async {
  final controller = ProfileController(_MemoryProfiles());
  await controller.initialize();
  return controller;
}

final class _MemoryProfiles implements ProfileRepository {
  final _profiles = <Profile>[
    _profile('default', '我的日志', true),
    _profile('child', '孩子', false),
  ];
  String? _active;

  @override
  Future<void> archive(String id) async {}
  @override
  Future<Profile> create({required String name}) async {
    final profile = _profile('new', name, false);
    _profiles.add(profile);
    return profile;
  }

  @override
  Future<Profile> ensureDefaultProfile() async => _profiles.first;
  @override
  Future<List<Profile>> listActive() async => _profiles;
  @override
  Future<String?> readActiveProfileId() async => _active;
  @override
  Future<void> rename({required String id, required String name}) async {}
  @override
  Future<void> writeActiveProfileId(String id) async {
    _active = id;
  }
}

Profile _profile(String id, String name, bool isDefault) => Profile(
  id: id,
  name: name,
  avatarPath: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  isDefault: isDefault,
  isArchived: false,
);
