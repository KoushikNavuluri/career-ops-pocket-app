import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import 'tools_repository.dart';

class StudioScreen extends ConsumerWidget {
  const StudioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(writingToolsProvider);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000 ? 3 : (width >= 600 ? 2 : 1);

    Widget card(IconData icon, String title, String body, VoidCallback onTap) => PocketCard(
          onTap: onTap,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: context.colors.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: 4),
                Text(body, style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
              ]),
            ),
          ]),
        );

    Widget grid(List<Widget> children) => GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: columns == 1 ? 4.2 : 2.6,
          children: children,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Studio')),
      body: ContentWidth(
        maxWidth: 1100,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Eyebrow('Your toolkit'),
            const SizedBox(height: 10),
            grid([
              card(Icons.description_outlined, 'Resume workspace', 'Your master CV, versions and previews.', () => context.push('/cv')),
              card(Icons.auto_awesome, 'Career assistant', 'Grounded in your pipeline and CV.', () => context.push('/assistant')),
              card(Icons.menu_book_outlined, 'Story bank', 'STAR + Reflection proof stories.', () => context.push('/stories')),
              card(Icons.folder_open_outlined, 'Documents', 'Drafts and reports you saved.', () => context.push('/documents')),
            ]),
            const SizedBox(height: 24),
            const Eyebrow('Writing studio'),
            const SizedBox(height: 10),
            tools.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(writingToolsProvider)),
              data: (items) => grid([
                for (final t in items) card(Icons.edit_note, t.title, t.description, () => context.push('/tools/${t.id}')),
              ]),
            ),
            const SizedBox(height: 16),
            Text('Drafts are saved to Documents. Nothing is ever sent for you.',
                style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground)),
          ],
        ),
      ),
    );
  }
}
