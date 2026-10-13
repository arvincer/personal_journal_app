import 'package:flutter/material.dart';
import 'package:personal_journal_app/core/files/app_file_store.dart';
import 'package:personal_journal_app/features/entries/entry.dart';
import 'package:personal_journal_app/features/entries/entry_repository.dart';
import 'package:personal_journal_app/features/entries/media_item.dart';
import 'package:personal_journal_app/features/entries/media_repository.dart';

abstract interface class EntryDeletionService {
  Future<void> delete(JournalEntry entry);
}

final class DefaultEntryDeletionService implements EntryDeletionService {
  DefaultEntryDeletionService({
    required this.entryRepository,
    required this.mediaRepository,
    required this.fileStore,
  });

  final EntryRepository entryRepository;
  final MediaRepository mediaRepository;
  final AppFileStore fileStore;

  @override
  Future<void> delete(JournalEntry entry) async {
    final media = await mediaRepository.listForEntry(entry.id);
    await entryRepository.deleteEntry(entry.id);
    for (final item in media) {
      await _deleteBestEffort(item.relativePath);
      final thumbnail = item.thumbnailPath;
      if (thumbnail != null) await _deleteBestEffort(thumbnail);
    }
  }

  Future<void> _deleteBestEffort(String path) async {
    try {
      await fileStore.deleteRelative(path);
    } catch (_) {
      // Database state is already authoritative; inaccessible residual files
      // are safe to retry during later storage maintenance.
    }
  }
}

class EntryEditorPage extends StatefulWidget {
  const EntryEditorPage({
    required this.entry,
    required this.entryRepository,
    required this.mediaRepository,
    required this.deletionService,
    super.key,
  });

  final JournalEntry entry;
  final EntryRepository entryRepository;
  final MediaRepository mediaRepository;
  final EntryDeletionService deletionService;

  @override
  State<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends State<EntryEditorPage> {
  late final TextEditingController _text = TextEditingController(
    text: widget.entry.text,
  );
  List<MediaItem> _media = const <MediaItem>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    final media = await widget.mediaRepository.listForEntry(widget.entry.id);
    if (mounted) setState(() => _media = media);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.entryRepository.updateText(
        entryId: widget.entry.id,
        text: _text.text,
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录？'),
        content: const Text('记录和所有附件将被删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.deletionService.delete(widget.entry);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.entry.createdAt.add(
      Duration(minutes: widget.entry.timezoneOffsetMinutes),
    );
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        title: Text(time),
        actions: <Widget>[
          IconButton(
            key: const Key('entry-editor-delete'),
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('entry-editor-text'),
                controller: _text,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            for (final item in _media)
              TextFormField(
                initialValue: item.caption,
                decoration: InputDecoration(labelText: item.originalFilename),
                onFieldSubmitted: (caption) =>
                    widget.mediaRepository.updateCaption(
                      mediaId: item.id,
                      caption: caption.isEmpty ? null : caption,
                    ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('entry-editor-save'),
              onPressed: _saving ? null : _save,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
