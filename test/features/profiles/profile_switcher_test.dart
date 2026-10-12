import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';
import 'package:personal_journal_app/features/profiles/profile_switcher.dart';

void main() {
  testWidgets('shows active profile and switches to child', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileSwitcher(controller: controller)),
      ),
    );
    expect(find.text('我的日志'), findsOneWidget);
    await tester.tap(find.text('我的日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('孩子'));
    await tester.pumpAndSettle();
    expect(controller.active?.id, 'child');
    expect(find.text('孩子'), findsOneWidget);
  });

  testWidgets('creates and selects a new profile from dialog', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileSwitcher(controller: controller)),
      ),
    );
    await tester.tap(find.text('我的日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建新用户'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新用户');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(controller.active?.name, '新用户');
    expect(find.text('新用户'), findsOneWidget);
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
    final profile = _profile('new-${_profiles.length}', name, false);
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
