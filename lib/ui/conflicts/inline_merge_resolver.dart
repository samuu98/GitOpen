import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/diff/merge_conflict.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// In-place 3-way merge resolver for a single conflicted file.
///
/// Loads the working-tree file (with conflict markers) via `readWorkingFile`,
/// parses it with [MergeConflictParser], and renders each conflict region with
/// per-conflict "Use ours / Use theirs / Use both" choices. Plain regions are
/// shown as read-only context. Saving assembles the resolved text, writes it
/// back with `writeWorkingFile`, then stages the path so git considers the
/// conflict resolved — at which point [onResolved] fires so the host can drop
/// the file from its conflict list.
///
/// When the file has no parseable markers (binary, unusual encoding) it shows
/// an explanatory message and an "Open external editor" action that calls
/// [onOpenExternal].
///
/// This widget owns no chrome: it renders a bare [Column] sized to its content
/// (capped + internally scrollable) so it can sit inline inside a card, a
/// dialog, or a panel.
class InlineMergeResolver extends ConsumerStatefulWidget {
  const InlineMergeResolver({
    required this.repo,
    required this.relativePath,
    required this.onResolved,
    required this.onOpenExternal,
    super.key,
  });

  final RepoLocation repo;
  final String relativePath;

  /// Called after the resolved file is written and staged.
  final VoidCallback onResolved;

  /// Called when the user asks to edit the file in the external editor instead
  /// (offered both as a manual action and as the fallback when the file has no
  /// parseable conflict markers).
  final VoidCallback onOpenExternal;

  @override
  ConsumerState<InlineMergeResolver> createState() =>
      _InlineMergeResolverState();
}

class _InlineMergeResolverState extends ConsumerState<InlineMergeResolver> {
  late Future<List<Segment>> _segmentsFuture;

  /// Choice per conflict, keyed by the conflict's index within the segment
  /// list (matching the contract of [assembleResolution]).
  final Map<int, Choice> _choices = {};

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _segmentsFuture = _load();
  }

  Future<List<Segment>> _load() async {
    final read = ref.read(gitReadOperationsProvider);
    final content = await read.readWorkingFile(
      widget.repo,
      widget.relativePath,
    );
    return const MergeConflictParser().parse(content);
  }

  /// Indices (into the segment list) of every conflict, in document order.
  List<int> _conflictIndices(List<Segment> segments) => [
        for (var i = 0; i < segments.length; i++)
          if (segments[i] is ConflictSegment) i,
      ];

  bool _allResolved(List<Segment> segments) =>
      _conflictIndices(segments).every(_choices.containsKey);

  Future<void> _save(List<Segment> segments) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final resolved = assembleResolution(segments, _choices);
    final write = ref.read(gitWriteOperationsProvider);
    final writeResult = await write.writeWorkingFile(
      widget.repo,
      widget.relativePath,
      resolved,
    );
    if (writeResult case GitFailure(:final message)) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Failed to write file: $message';
      });
      return;
    }
    final stageResult =
        await write.stageFiles(widget.repo, [widget.relativePath]);
    if (!mounted) return;
    if (stageResult case GitFailure(:final message)) {
      setState(() {
        _saving = false;
        _error = 'Saved, but failed to stage: $message';
      });
      return;
    }
    setState(() => _saving = false);
    widget.onResolved();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FutureBuilder<List<Segment>>(
      future: _segmentsFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Message(
            icon: Icons.error_outline,
            color: palette.accentErr,
            text: 'Could not read file: ${snap.error}',
            palette: palette,
          );
        }
        if (!snap.hasData) {
          return SizedBox(
            height: 80,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.fg3,
                ),
              ),
            ),
          );
        }

        final segments = snap.data!;
        final conflictIndices = _conflictIndices(segments);

        // Graceful fallback: nothing to resolve in-app.
        if (conflictIndices.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Message(
                icon: Icons.info_outline,
                color: palette.accentRemote,
                text: 'No conflict markers were found in this file. It may '
                    'already be resolved, or use an encoding the in-app editor '
                    "can't parse. Open it in the external editor instead.",
                palette: palette,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton.secondary(
                  label: 'Open external editor',
                  onPressed: widget.onOpenExternal,
                ),
              ),
            ],
          );
        }

        final resolvedCount =
            conflictIndices.where(_choices.containsKey).length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$resolvedCount of ${conflictIndices.length} '
                'conflict${conflictIndices.length == 1 ? '' : 's'} resolved',
                style: TextStyle(color: palette.fg2, fontSize: 12),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < segments.length; i++)
                      _segmentView(i, segments[i], palette),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.error_outline, size: 14, color: palette.accentErr),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _error!,
                      style:
                          TextStyle(color: palette.accentErr, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                AppButton.secondary(
                  label: 'Open external editor',
                  onPressed: _saving ? null : widget.onOpenExternal,
                ),
                const Spacer(),
                AppButton.primary(
                  label: 'Save resolution',
                  onPressed: (_saving || !_allResolved(segments))
                      ? null
                      : () => _save(segments),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _segmentView(int index, Segment seg, AppPalette palette) {
    return switch (seg) {
      PlainSegment(:final text) => _PlainView(text: text, palette: palette),
      ConflictSegment() => _ConflictView(
          segment: seg,
          choice: _choices[index],
          palette: palette,
          onChoose: (c) => setState(() => _choices[index] = c),
        ),
    };
  }
}

class _PlainView extends StatelessWidget {
  const _PlainView({required this.text, required this.palette});
  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // Trailing newline produces an empty visual line; trim only the final one
    // for display so context regions don't add a blank gap.
    final display =
        text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
    if (display.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        display,
        style: TextStyle(
          color: palette.fg2,
          fontSize: 12,
          fontFamily: 'monospace',
          height: 1.35,
        ),
      ),
    );
  }
}

class _ConflictView extends StatelessWidget {
  const _ConflictView({
    required this.segment,
    required this.choice,
    required this.palette,
    required this.onChoose,
  });

  final ConflictSegment segment;
  final Choice? choice;
  final AppPalette palette;
  final ValueChanged<Choice> onChoose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border.all(
          color: choice == null ? palette.accentTag : palette.accentCurrent,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidePane(
            label: segment.oursLabel.isEmpty
                ? 'Ours'
                : 'Ours (${segment.oursLabel})',
            body: segment.ours,
            accent: palette.accentCurrent,
            palette: palette,
            highlighted: choice == Choice.ours ||
                choice == Choice.both ||
                choice == Choice.bothReversed,
          ),
          if (segment.base != null)
            _SidePane(
              label: segment.baseLabel.isEmpty
                  ? 'Base'
                  : 'Base (${segment.baseLabel})',
              body: segment.base!,
              accent: palette.fg3,
              palette: palette,
              highlighted: false,
            ),
          _SidePane(
            label: segment.theirsLabel.isEmpty
                ? 'Theirs'
                : 'Theirs (${segment.theirsLabel})',
            body: segment.theirs,
            accent: palette.accentRemote,
            palette: palette,
            highlighted: choice == Choice.theirs ||
                choice == Choice.both ||
                choice == Choice.bothReversed,
          ),
          Divider(height: 1, thickness: 1, color: palette.border),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ChoiceChip(
                  label: 'Use ours',
                  selected: choice == Choice.ours,
                  palette: palette,
                  onTap: () => onChoose(Choice.ours),
                ),
                _ChoiceChip(
                  label: 'Use theirs',
                  selected: choice == Choice.theirs,
                  palette: palette,
                  onTap: () => onChoose(Choice.theirs),
                ),
                _ChoiceChip(
                  label: 'Use both',
                  selected: choice == Choice.both,
                  palette: palette,
                  onTap: () => onChoose(Choice.both),
                ),
                _ChoiceChip(
                  label: 'Both (theirs first)',
                  selected: choice == Choice.bothReversed,
                  palette: palette,
                  onTap: () => onChoose(Choice.bothReversed),
                ),
                if (choice != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle,
                      size: 15, color: palette.accentCurrent),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidePane extends StatelessWidget {
  const _SidePane({
    required this.label,
    required this.body,
    required this.accent,
    required this.palette,
    required this.highlighted,
  });

  final String label;
  final String body;
  final Color accent;
  final AppPalette palette;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final display =
        body.endsWith('\n') ? body.substring(0, body.length - 1) : body;
    return Container(
      width: double.infinity,
      color: highlighted ? accent.withValues(alpha: 0.10) : null,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            display.isEmpty ? '(empty)' : display,
            style: TextStyle(
              color: display.isEmpty ? palette.fg3 : palette.fg0,
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.35,
              fontStyle: display.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? palette.accentCurrent : palette.bg3,
            border: Border.all(
              color: selected ? palette.accentCurrent : palette.borderStrong,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : palette.fg1,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.color,
    required this.text,
    required this.palette,
  });

  final IconData icon;
  final Color color;
  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: palette.fg1, fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}
