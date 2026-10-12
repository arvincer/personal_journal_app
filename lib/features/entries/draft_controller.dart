import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';

final class DraftController extends ChangeNotifier {
  DraftController(this._repository) {
    textController.addListener(_scheduleSave);
  }

  static const _debounceDuration = Duration(milliseconds: 400);

  final EntryRepository _repository;
  final TextEditingController textController = TextEditingController();
  Future<void> _operationQueue = Future<void>.value();
  Timer? _debounce;
  String? _profileId;
  bool _writingEditor = false;
  bool _closing = false;
  bool _notifierDisposed = false;
  Future<void>? _closeFuture;

  String? get profileId => _profileId;

  Future<void> initialize(String profileId) => _enqueue(() async {
    _profileId = profileId;
    await _loadDraft();
    _notifyIfOpen();
  });

  Future<void> switchProfile(String profileId) => _enqueue(() async {
    if (_profileId == profileId) {
      return;
    }
    _debounce?.cancel();
    await _flushCurrent();
    _profileId = profileId;
    await _loadDraft();
    _notifyIfOpen();
  });

  Future<void> flush() {
    _debounce?.cancel();
    return _enqueue(_flushCurrent);
  }

  Future<JournalEntry> publish() => _enqueue(() async {
    await _flushCurrent();
    final profileId = _requireProfileId();
    final published = await _repository.publishDraft(profileId);
    await _repository.saveDraft(profileId: profileId, text: '');
    _writeEditorText('');
    _notifyIfOpen();
    return published;
  });

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _closing = true;
    _debounce?.cancel();
    return _closeFuture = _finishClose();
  }

  Future<void> _finishClose() async {
    await _enqueue(_flushCurrent);
    textController.removeListener(_scheduleSave);
    textController.dispose();
    _disposeNotifier();
  }

  Future<void> _loadDraft() async {
    final profileId = _requireProfileId();
    final draft = await _repository.getDraft(profileId);
    _writeEditorText(draft?.text ?? '');
  }

  Future<void> _flushCurrent() async {
    final profileId = _profileId;
    if (profileId == null) {
      return;
    }
    await _repository.saveDraft(
      profileId: profileId,
      text: textController.text,
    );
  }

  void _scheduleSave() {
    if (_writingEditor || _closing || _profileId == null) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      unawaited(flush());
    });
  }

  void _writeEditorText(String text) {
    _writingEditor = true;
    textController.text = text;
    _writingEditor = false;
  }

  String _requireProfileId() {
    final profileId = _profileId;
    if (profileId == null) {
      throw StateError('A profile must be selected before editing a draft.');
    }
    return profileId;
  }

  void _notifyIfOpen() {
    if (!_closing) {
      notifyListeners();
    }
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
    if (!_closing) {
      unawaited(close());
    }
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }

  void _disposeNotifier() {
    if (_notifierDisposed) {
      return;
    }
    _notifierDisposed = true;
    super.dispose();
  }
}
