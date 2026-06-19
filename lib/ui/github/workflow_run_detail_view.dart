import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/github/github_api_state.dart';
import 'package:gitopen/ui/github/github_providers.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

/// Icon + colour for a workflow run / job / step given its raw status and
/// conclusion (shared by the runs list and this detail view).
(IconData, Color) workflowStatusVisual(
  String status,
  String? conclusion,
  AppPalette palette,
) {
  if (status != 'completed') return (Icons.timelapse, palette.accentWarn);
  return switch (conclusion) {
    'success' => (Icons.check_circle_outline, palette.accentCurrent),
    'failure' => (Icons.cancel_outlined, palette.accentErr),
    'cancelled' => (Icons.do_not_disturb_on_outlined, palette.fg3),
    'skipped' => (Icons.skip_next_outlined, palette.fg3),
    _ => (Icons.remove_circle_outline, palette.fg3),
  };
}

String _fmtDuration(Duration d) => '${d.inMinutes}m ${d.inSeconds % 60}s';

/// A workflow run's jobs and steps, with rerun / cancel actions and per-job
/// logs. Auto-refreshes while any job is still running.
class WorkflowRunDetailView extends ConsumerStatefulWidget {
  const WorkflowRunDetailView({
    required this.slug,
    required this.token,
    required this.run,
    required this.onBack,
    super.key,
  });

  final RepoSlug slug;
  final String token;
  final WorkflowRunInfo run;
  final VoidCallback onBack;

  @override
  ConsumerState<WorkflowRunDetailView> createState() =>
      _WorkflowRunDetailViewState();
}

class _WorkflowRunDetailViewState extends ConsumerState<WorkflowRunDetailView> {
  static const _pollInterval = Duration(seconds: 5);
  Timer? _poll;

  ({RepoSlug slug, String token, int runId}) get _key =>
      (slug: widget.slug, token: widget.token, runId: widget.run.id);

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Schedule a single refresh while work is ongoing; cancel once terminal.
  /// One-shot (not periodic) so it never blocks `pumpAndSettle` once done.
  void _schedulePoll({required bool ongoing}) {
    _poll?.cancel();
    if (!ongoing) return;
    _poll = Timer(_pollInterval, () {
      if (mounted) ref.invalidate(githubWorkflowJobsProvider(_key));
    });
  }

  Future<void> _act(Future<void> Function() op) async {
    try {
      await op();
      ref.invalidate(githubWorkflowJobsProvider(_key));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(githubWorkflowJobsProvider(_key));
    final jobs = async.value;
    final ongoing = jobs == null
        ? !widget.run.isCompleted
        : jobs.any((j) => !j.isCompleted);
    _schedulePoll(ongoing: ongoing);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => GitHubApiErrorView(
              error: e,
              onRetry: () => ref.invalidate(githubWorkflowJobsProvider(_key)),
            ),
            data: (jobs) => ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final job in jobs)
                  _JobTile(slug: widget.slug, token: widget.token, job: job),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final palette = AppPalette.of(context);
    final run = widget.run;
    final (icon, color) = workflowStatusVisual(
      run.status,
      run.conclusion,
      palette,
    );
    final failed = run.conclusion == 'failure';
    return Container(
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back to runs',
            onPressed: widget.onBack,
          ),
          const SizedBox(width: 4),
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              run.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.fg0, fontSize: 13),
            ),
          ),
          Text(
            run.headBranch,
            style: TextStyle(color: palette.accentRemote, fontSize: 11),
          ),
          const SizedBox(width: 4),
          if (!run.isCompleted)
            AppIconButton(
              icon: Icons.cancel_outlined,
              tooltip: 'Cancel run',
              onPressed: () => _act(
                () => ref
                    .read(gitHubApiProvider)
                    .cancelWorkflowRun(
                      widget.slug,
                      run.id,
                      token: widget.token,
                    ),
              ),
            ),
          if (failed)
            AppIconButton(
              icon: Icons.replay_circle_filled_outlined,
              tooltip: 'Re-run failed jobs',
              onPressed: () => _act(
                () => ref
                    .read(gitHubApiProvider)
                    .rerunFailedJobs(widget.slug, run.id, token: widget.token),
              ),
            ),
          AppIconButton(
            icon: Icons.refresh,
            tooltip: 'Re-run all jobs',
            onPressed: () => _act(
              () => ref
                  .read(gitHubApiProvider)
                  .rerunWorkflowRun(widget.slug, run.id, token: widget.token),
            ),
          ),
          AppIconButton(
            icon: Icons.open_in_new,
            tooltip: 'Open on GitHub',
            onPressed: () => launchUrl(
              Uri.parse(run.htmlUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }
}

class _JobTile extends ConsumerWidget {
  const _JobTile({required this.slug, required this.token, required this.job});

  final RepoSlug slug;
  final String token;
  final WorkflowJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final (icon, color) = workflowStatusVisual(
      job.status,
      job.conclusion,
      palette,
    );
    final duration = job.duration;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    job.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.fg0, fontSize: 12.5),
                  ),
                ),
                if (duration != null)
                  Text(
                    _fmtDuration(duration),
                    style: TextStyle(color: palette.fg3, fontSize: 11),
                  ),
                const SizedBox(width: 4),
                AppIconButton(
                  icon: Icons.article_outlined,
                  tooltip: 'View job log',
                  onPressed: () => WorkflowLogDialog.show(
                    context,
                    slug: slug,
                    token: token,
                    jobId: job.id,
                    jobName: job.name,
                  ),
                ),
              ],
            ),
          ),
          for (final step in job.steps) _StepRow(step: step),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final WorkflowStep step;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (icon, color) = workflowStatusVisual(
      step.status,
      step.conclusion,
      palette,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 12, top: 1, bottom: 1),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.fg1, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal showing a single job's full log text, fetched on open.
class WorkflowLogDialog extends ConsumerStatefulWidget {
  const WorkflowLogDialog({
    required this.slug,
    required this.token,
    required this.jobId,
    required this.jobName,
    super.key,
  });

  final RepoSlug slug;
  final String token;
  final int jobId;
  final String jobName;

  static Future<void> show(
    BuildContext context, {
    required RepoSlug slug,
    required String token,
    required int jobId,
    required String jobName,
  }) => showDialog<void>(
    context: context,
    builder: (_) => WorkflowLogDialog(
      slug: slug,
      token: token,
      jobId: jobId,
      jobName: jobName,
    ),
  );

  @override
  ConsumerState<WorkflowLogDialog> createState() => _WorkflowLogDialogState();
}

class _WorkflowLogDialogState extends ConsumerState<WorkflowLogDialog> {
  late final Future<String> _log = ref
      .read(gitHubApiProvider)
      .jobLogs(widget.slug, widget.jobId, token: widget.token);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog(
      child: SizedBox(
        width: 760,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Log — ${widget.jobName}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.fg0,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<String>(
                future: _log,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Could not load the log:\n${snapshot.error}',
                          style: TextStyle(color: palette.accentErr),
                        ),
                      ),
                    );
                  }
                  final text = snapshot.data ?? '';
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        text.isEmpty ? '(empty log)' : text,
                        style: TextStyle(
                          color: palette.fg1,
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
