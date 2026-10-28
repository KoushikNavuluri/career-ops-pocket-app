import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import 'jobs_repository.dart';
import 'models.dart';
import 'widgets.dart';

class PipelineScreen extends ConsumerStatefulWidget {
  const PipelineScreen({super.key});

  @override
  ConsumerState<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends ConsumerState<PipelineScreen> {
  String? _status;
  String _query = '';
  String _sort = 'recent';
  double? _minScore;

  Future<void> _export() async {
    try {
      final csv = await ref.read(jobsActionsProvider).exportCsv();
      await Clipboard.setData(ClipboardData(text: csv));
      if (mounted) showMessage(context, 'Pipeline CSV copied to your clipboard.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider);
    final date = DateFormat.MMMd();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pipeline'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'recent', child: Text('Recent')),
              PopupMenuItem(value: 'score', child: Text('Score')),
              PopupMenuItem(value: 'company', child: Text('Company')),
            ],
          ),
          PopupMenuButton<double>(
            tooltip: 'Fit',
            icon: const Icon(Icons.filter_alt_outlined),
            onSelected: (v) => setState(() => _minScore = v <= 0 ? null : v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0, child: Text('Any score')),
              PopupMenuItem(value: 4.0, child: Text('4 and up')),
              PopupMenuItem(value: 4.5, child: Text('4.5 and up')),
            ],
          ),
          IconButton(tooltip: 'Export CSV', icon: const Icon(Icons.ios_share), onPressed: _export),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add a role',
        onPressed: () => showAddJobSheet(context),
        child: const Icon(Icons.add),
      ),
      body: jobs.when(
        loading: () => const SkeletonList(),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(jobsProvider)),
        data: (all) {
          final counts = <String, int>{for (final s in kStatuses) s: all.where((j) => j.status == s).length};
          final visible = filterJobs(all, query: _query, status: _status, minScore: _minScore, sort: _sort);
          return ContentWidth(
            maxWidth: 1000,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: pocketInput(context, hint: 'Find a company or role…', prefixIcon: const Icon(Icons.search)),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(label: Text('All ${all.length}'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                      ),
                      for (final s in kStatuses)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(label: Text('$s ${counts[s]}'), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? EmptyState(
                          icon: Icons.inbox_outlined,
                          title: _query.isNotEmpty ? 'Nothing matches "$_query"' : 'Nothing here yet',
                          message: _query.isNotEmpty ? 'Clear the search to see everything.' : 'Roles you add appear here as they move through your search.',
                          actionLabel: 'Add a role',
                          onAction: () => showAddJobSheet(context),
                        )
                      : RefreshIndicator(
                          onRefresh: () => ref.refresh(jobsProvider.future),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (_, i) {
                              final j = visible[i];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                onTap: () => context.push('/job/${j.id}'),
                                title: Text(j.role, style: context.text.titleSmall),
                                subtitle: Text('${j.company} · added ${date.format(j.createdAt)}',
                                    style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [StatusChip(j.status), const SizedBox(height: 4), if (j.score != null) ScoreBadge(j.score)],
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
