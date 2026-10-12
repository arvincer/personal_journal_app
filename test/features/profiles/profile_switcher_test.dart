import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:personal_journal_app/features/profiles/profile_controller.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';
import 'package:personal_journal_app/features/profiles/profile_switcher.dart';

void main() {
  testWidgets('shows the active profile and switches to a child', (
    tester,
  ) async {
    final controller = await _controller(_MemoryProfiles());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileSwitcher(controller: controller)),
      ),
    );
    expect(find.text('Default'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MenuItemButton).at(1));
    await tester.pumpAndSettle();
    expect(controller.active?.id, 'child');
  });

  testWidgets('ignores repeated taps while a profile selection is pending', (
    tester,
  ) async {
    final repository = _DelayedSelectionProfiles();
    final controller = await _controller(repository);
    repository.writeCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileSwitcher(controller: controller)),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    final child = find.byType(MenuItemButton).at(1);
    await tester.tap(child);
    await tester.tap(child);
    await tester.pump();
    expect(repository.writeCalls, 1);
    repository.completeSelection();
    await tester.pumpAndSettle();
  });
}

Future<ProfileController> _controller(ProfileRepository repository) async {
  final controller = ProfileController(repository);
  await controller.initialize();
  return controller;
}

class _MemoryProfiles implements ProfileRepository {
  final profiles = <Profile>[
    _profile('default', 'Default', true),
    _profile('child', 'Child', false),
  ];
  String? active;
  @override
  Future<void> archive(String id) async {}
  @override
  Future<Profile> create({required String name}) async {
    final value = _profile('new', name, false);
    profiles.add(value);
    return value;
  }

  @override
  Future<Profile> ensureDefaultProfile() async => profiles.first;
  @override
  Future<List<Profile>> listActive() async => profiles;
  @override
  Future<String?> readActiveProfileId() async => active;
  @override
  Future<void> rename({required String id, required String name}) async {}
  @override
  Future<void> writeActiveProfileId(String id) async {
    active = id;
  }
}

class _DelayedSelectionProfiles extends _MemoryProfiles {
  final selection = Completer<void>();
  int writeCalls = 0;
  void completeSelection() => selection.complete();
  @override
  Future<void> writeActiveProfileId(String id) async {
    writeCalls++;
    if (id == 'child') await selection.future;
    await super.writeActiveProfileId(id);
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
