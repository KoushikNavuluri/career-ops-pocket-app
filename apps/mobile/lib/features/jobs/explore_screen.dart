import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import 'jobs_repository.dart';
import 'models.dart';
import 'widgets.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  String _tab = 'all';
  String _query = '';
  String? _workModel;
  double? _minScore;
  String _sort = 'recent';

  Future<void> _filters() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void update(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Make room for the right roles', style: ctx.text.headlineSmall),
                const SizedBox(height: 16),
                Text('Work model', style: ctx.text.titleSmall),
                Wrap(spacing: 8, children: [
                  ChoiceChip(label: const Text('Any location'), selected: _workModel == null, onSelected: (_) => update(() => _workModel = null)),
                  for (final w in kWorkModels)
                    ChoiceChip(label: Text(w), selected: _workModel == w, onSelected: (_) => update(() => _workModel = w)),
                ]),
                const SizedBox(height: 12),
                Text('Minimum fit score', style: ctx.text.titleSmall),
                Wrap(spacing: 8, children: [
                  for (final s in const [null, 4.0, 4.5])
                    ChoiceChip(
                      label: Text(s == null ? 'Any score' : s.toString()),
                      selected: _minScore == s,
                      onSelected: (_) => update(() => _minScore = s),
                    ),
                ]),
                const SizedBox(height: 12),
                Text('Sort by', style: ctx.text.titleSmall),
                Wrap(spacing: 8, children: [
                  ChoiceChip(label: const Text('Newest'), selected: _sort == 'recent', onSelected: (_) => update(() => _sort = 'recent')),
                  ChoiceChip(label: const Text('Best fit'), selected: _sort == 'score', onSelected: (_) => update(() => _sort = 'score')),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  TextButton(
                    onPressed: () => update(() {
                      _workModel = null;
                      _minScore = null;
                      _sort = 'recent';
                    }),
                    child: const Text('Reset'),
                  ),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Show roles')),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Explore'), actions: [
        IconButton(tooltip: 'Filters', icon: const Icon(Icons.tune), onPressed: _filters),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddJobSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add a role'),
      ),
      body: ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: pocketInput(context, hint: 'Role, company, or skill…', prefixIcon: const Icon(Icons.search)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('For you')),
                  ButtonSegment(value: 'new', label: Text('New')),
                  ButtonSegment(value: 'saved', label: Text('Saved')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: jobs.when(
                loading: () => const SkeletonList(),
                error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(jobsProvider)),
                data: (all) {
                  final visible = filterJobs(
                    all.where((j) => j.status != 'Discarded' && j.status != 'SKIP').toList(),
                    query: _query,
                    status: _tab == 'new' ? 'Inbox' : null,
                    savedOnly: _tab == 'saved',
                    minScore: _minScore,
                    workModel: _workModel,
                    sort: _sort,
                  );
                  if (visible.isEmpty) {
                    return EmptyState(
                      icon: Icons.travel_explore,
                      title: all.isEmpty ? 'No opportunities yet' : 'No roles match',
                      message: all.isEmpty ? 'Paste a job description to start.' : 'Try clearing a filter or the search.',
                      actionLabel: 'Add a job description',
                      onAction: () => showAddJobSheet(context),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () => ref.refresh(jobsProvider.future),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => JobCard(job: visible[i]),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Scores are AI judgments from your own evidence. Verify every posting before acting.',
                style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
