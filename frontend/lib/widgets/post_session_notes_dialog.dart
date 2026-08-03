import 'dart:async';

import 'package:flutter/material.dart';

import '../providers/session_provider.dart';
import '../theme/app_style.dart';

class PostSessionNotesDialog extends StatefulWidget {
  final SessionProvider session;

  const PostSessionNotesDialog({super.key, required this.session});

  @override
  State<PostSessionNotesDialog> createState() => _PostSessionNotesDialogState();
}

class _PostSessionNotesDialogState extends State<PostSessionNotesDialog> {
  final _notesController = TextEditingController();
  bool _isEnding = true;
  bool _isSaving = false;
  bool _endFailed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_endSession());
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _endSession() async {
    setState(() {
      _isEnding = true;
      _endFailed = false;
      _errorMessage = null;
    });
    final success = await widget.session.endSession();
    if (!mounted) return;
    setState(() {
      _isEnding = false;
      _endFailed = !success;
      _errorMessage = success ? null : widget.session.errorMessage;
    });
  }

  Future<void> _save(String notes) async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final success = await widget.session.updatePostSessionNotes(notes);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSaving = false;
      _errorMessage = widget.session.errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Zakończenie sesji'),
        content: SizedBox(
          width: 460,
          child: _isEnding
              ? const _ProgressMessage()
              : _endFailed
              ? _EndError(
                  message: _errorMessage,
                  onRetry: _endSession,
                  onCancel: () => Navigator.of(context).pop(),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notatki po sesji',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('post-session-notes-field'),
                      controller: _notesController,
                      enabled: !_isSaving,
                      minLines: 4,
                      maxLines: 7,
                      maxLength: 10000,
                      autofocus: true,
                      decoration: appInputDecoration(
                        'Opcjonalne obserwacje po zakończeniu sesji',
                      ).copyWith(alignLabelWithHint: true),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],
                  ],
                ),
        ),
        actions: _isEnding || _endFailed
            ? null
            : [
                TextButton(
                  key: const ValueKey('skip-post-session-notes'),
                  onPressed: _isSaving ? null : () => _save(''),
                  child: const Text('Pomiń'),
                ),
                ElevatedButton(
                  key: const ValueKey('save-post-session-notes'),
                  onPressed: _isSaving
                      ? null
                      : () => _save(_notesController.text),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Zapisz i pokaż podsumowanie'),
                ),
              ],
      ),
    );
  }
}

class _ProgressMessage extends StatelessWidget {
  const _ProgressMessage();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Kończenie sesji i zapisywanie danych…')),
        ],
      ),
    );
  }
}

class _EndError extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _EndError({
    required this.message,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message ?? 'Nie udało się zakończyć sesji.',
          style: TextStyle(color: Colors.red.shade700),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onCancel, child: const Text('Anuluj')),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: onRetry, child: const Text('Ponów')),
          ],
        ),
      ],
    );
  }
}
