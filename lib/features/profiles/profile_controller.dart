import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:personal_journal_app/features/profiles/profile.dart';
import 'package:personal_journal_app/features/profiles/profile_repository.dart';

final class ProfileController extends ChangeNotifier {
  ProfileController(this._repository);

  final ProfileRepository _repository;

  List<Profile> _profiles = const <Profile>[];
  Profile? _active;
  bool _loading = false;
  bool _disposed = false;
  Future<void> _operationQueue = Future<void>.value();

  List<Profile> get profiles => UnmodifiableListView<Profile>(_profiles);
  Profile? get active => _active;
  bool get loading => _loading;

  Future<void> initialize() {
    if (!_disposed) {
      _loading = true;
      notifyListeners();
    }
    return _enqueue(_initialize);
  }

  Future<void> _initialize() async {
    try {
      await _repository.ensureDefaultProfile();
      final loadedProfiles = await _repository.listActive();
      final persistedId = await _repository.readActiveProfileId();
      final restored = _findById(loadedProfiles, persistedId);
      final nextActive = restored ?? _preferredProfile(loadedProfiles);
      if (nextActive == null) {
        throw StateError('No active profile is available.');
      }
      if (restored == null) {
        await _repository.writeActiveProfileId(nextActive.id);
      }
      if (_disposed) {
        return;
      }
      _profiles = loadedProfiles;
      _active = nextActive;
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<Profile> createAndSelect(String name) =>
      _enqueue(() => _createAndSelect(name));

  Future<Profile> _createAndSelect(String name) async {
    final created = await _repository.create(name: name);
    final loadedProfiles = await _repository.listActive();
    final selected = _findById(loadedProfiles, created.id);
    if (selected == null) {
      throw StateError('Created profile "${created.id}" is not active.');
    }
    await _repository.writeActiveProfileId(selected.id);
    if (!_disposed) {
      _profiles = loadedProfiles;
      _active = selected;
      notifyListeners();
    }
    return selected;
  }

  Future<void> select(String id) => _enqueue(() => _select(id));

  Future<void> _select(String id) async {
    final selected = _findById(_profiles, id);
    if (selected == null) {
      throw StateError('Cannot select unknown or archived profile "$id".');
    }
    await _repository.writeActiveProfileId(selected.id);
    if (!_disposed) {
      _active = selected;
      notifyListeners();
    }
  }

  Future<void> rename(String id, String name) =>
      _enqueue(() => _rename(id, name));

  Future<void> _rename(String id, String name) async {
    if (_findById(_profiles, id) == null) {
      throw StateError('Cannot rename unknown or archived profile "$id".');
    }
    final activeId = _active?.id;
    await _repository.rename(id: id, name: name);
    final loadedProfiles = await _repository.listActive();
    if (!_disposed) {
      _profiles = loadedProfiles;
      _active = _findById(loadedProfiles, activeId);
      notifyListeners();
    }
  }

  Future<void> archive(String id) => _enqueue(() => _archive(id));

  Future<void> _archive(String id) async {
    final target = _findById(_profiles, id);
    if (target == null) {
      throw StateError('Cannot archive unknown or archived profile "$id".');
    }
    if (_profiles.length == 1) {
      throw StateError('Cannot archive the last active profile.');
    }

    final wasActive = _active?.id == id;
    final activeId = _active?.id;
    await _repository.archive(id);
    final loadedProfiles = await _repository.listActive();
    final nextActive = wasActive
        ? _preferredProfile(loadedProfiles)
        : _findById(loadedProfiles, activeId);
    if (nextActive == null) {
      throw StateError('No active profile is available after archiving "$id".');
    }
    if (wasActive) {
      await _repository.writeActiveProfileId(nextActive.id);
    }
    if (!_disposed) {
      _profiles = loadedProfiles;
      _active = nextActive;
      notifyListeners();
    }
  }

  Profile? _preferredProfile(List<Profile> profiles) {
    for (final profile in profiles) {
      if (profile.isDefault) {
        return profile;
      }
    }
    return profiles.firstOrNull;
  }

  Profile? _findById(List<Profile> profiles, String? id) {
    if (id == null) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return null;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    super.dispose();
  }
}
