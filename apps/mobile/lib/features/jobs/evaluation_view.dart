import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/json.dart';
import 'models.dart';
import 'widgets.dart';

/// Renders the structured A-H report returned by GPT-5 mini.
class EvaluationView extends ConsumerWidget {
  const EvaluationView({super.key, required this.evaluation});
  final Evaluation evaluation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = evaluation.report;
    final muted = context.pocket.mutedForeground;
    final role = r.roleSummary;
    final legit = r.legitimacy;
    final comp = r.comp;
    final level = r.level;
    final interview = r.interview;

    Widget bullets(List<String> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(i))]),
              ),
          ],
        );

    Widget kv(String k, String v) => v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: RichText(
              text: TextSpan(style: context.text.bodyMedium, children: [
                TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: v),
              ]),
            ),
          );

    Widget section(String letter, String title, List<Widget> children, {bool initiallyExpanded = false}) => Card(
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: initiallyExpanded,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: context.pocket.sage, borderRadius: BorderRadius.circular(7)),
                  child: Text(letter, style: context.text.labelLarge),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: context.text.titleSmall)),
              ]),
              children: children,
            ),
          ),
        );

    Color matchColor(String m) => switch (m) {
          'Strong' => const Color(0xFF385515),
          'Partial' => const Color(0xFF6F3C00),
          'Missing' => const Color(0xFF71382E),
          _ => muted,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PocketCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScoreBadge(evaluation.score, large: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow(r.archetype.isEmpty ? 'Evaluation' : r.archetype),
                        const SizedBox(height: 4),
                        Text(r.decision, style: context.text.titleLarge),
                        Text('Confidence: ${r.confidence}', style: context.text.bodySmall?.copyWith(color: muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(r.verdict, style: context.text.bodyLarge),
              if (r.nextAction.isNotEmpty) ...[
                const SizedBox(height: 12),
                Notice('Next: ${r.nextAction}', icon: Icons.flag_outlined),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (r.topStrengths.isNotEmpty || r.softGaps.isNotEmpty || r.hardStops.isNotEmpty)
          PocketCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.topStrengths.isNotEmpty) ...[Text('Strengths', style: context.text.titleSmall), const SizedBox(height: 6), bullets(r.topStrengths)],
                if (r.softGaps.isNotEmpty) ...[const SizedBox(height: 10), Text('Gaps', style: context.text.titleSmall), const SizedBox(height: 6), bullets(r.softGaps)],
                if (r.hardStops.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Hard stops', style: context.text.titleSmall?.copyWith(color: context.colors.error)),
                  const SizedBox(height: 6),
                  bullets(r.hardStops),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        section('A', 'Role summary', [
          kv('TL;DR', str(role['tldr'])),
          kv('Domain', str(role['domain'])),
          kv('Function', str(role['function'])),
          kv('Seniority', str(role['seniority'])),
          kv('Work model', str(role['work_model'])),
          kv('Culture screen', '${str(role['culture_screen'])} ${str(role['culture_evidence'])}'.trim()),
          kv('Work authorization', str(role['work_auth']).replaceAll('_', ' ')),
          if (str(role['work_auth_quote']).isNotEmpty) Text('"${str(role['work_auth_quote'])}"', style: context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
        ], initiallyExpanded: true),
        const SizedBox(height: 8),
        section('B', 'Match with your CV', [
          for (final req in r.requirements)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(req.requirement, style: context.text.titleSmall)),
                    Text(req.match, style: context.text.labelLarge?.copyWith(color: matchColor(req.match))),
                  ]),
                  Text('${req.importance} · ${req.evidenceTier}', style: context.text.bodySmall?.copyWith(color: muted)),
                  if (req.jdSignal.isNotEmpty) Text('Posting: ${req.jdSignal}', style: context.text.bodySmall),
                  if (req.evidenceOrGap.isNotEmpty) Text('You: ${req.evidenceOrGap}', style: context.text.bodySmall),
                  if (req.mitigation.isNotEmpty) Text('Mitigation: ${req.mitigation}', style: context.text.bodySmall?.copyWith(color: context.colors.primary)),
                ],
              ),
            ),
          if (r.gapsStrategy.isNotEmpty) kv('Gaps strategy', r.gapsStrategy),
        ]),
        const SizedBox(height: 8),
        section('C', 'Level and strategy', [
          kv('Posting level', str(level['jd_level'])),
          kv('Your level', str(level['candidate_level'])),
          if (strList(level['sell_senior_without_lying']).isNotEmpty) ...[
            Text('Sell senior without lying', style: context.text.titleSmall),
            const SizedBox(height: 4),
            bullets(strList(level['sell_senior_without_lying'])),
          ],
          kv('If they downlevel you', str(level['if_downleveled'])),
        ]),
        const SizedBox(height: 8),
        section('D', 'Compensation and demand', [
          kv('Hiring entity', str(comp['hiring_entity'])),
          kv('Reliability', str(comp['reliability'])),
          kv('Advertised (verbatim)', str(comp['advertised_comp']).isEmpty ? 'Not stated' : str(comp['advertised_comp'])),
          kv('Notes', str(comp['notes'])),
          if (strList(comp['hr_questions']).isNotEmpty) ...[Text('Ask HR', style: context.text.titleSmall), bullets(strList(comp['hr_questions']))],
        ]),
        const SizedBox(height: 8),
        section('E', 'CV customization', [
          for (final c in r.customization)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(c['section']), style: context.text.titleSmall),
                Text(str(c['proposed_change'])),
                Text(str(c['why']), style: context.text.bodySmall?.copyWith(color: muted)),
              ]),
            ),
          if (r.keywords.isNotEmpty) ...[
            Text('Phrases worth mirroring', style: context.text.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final k in r.keywords) Chip(label: Text(k))]),
          ],
        ]),
        const SizedBox(height: 8),
        section('F', 'Interview plan', [
          for (final s in objList(interview['stories']))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(s['requirement']), style: context.text.titleSmall),
                Text(str(s['story'])),
                if (str(s['reflection']).isNotEmpty) Text('Reflection: ${str(s['reflection'])}', style: context.text.bodySmall?.copyWith(color: muted)),
              ]),
            ),
          for (final q in objList(interview['red_flag_questions']))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Q: ${str(q['question'])}', style: context.text.titleSmall),
                Text(str(q['honest_answer'])),
              ]),
            ),
        ]),
        const SizedBox(height: 8),
        section('G', 'Posting legitimacy · ${str(legit['tier'])}', [
          if (strList(legit['positive_signals']).isNotEmpty) ...[Text('Positive signals', style: context.text.titleSmall), bullets(strList(legit['positive_signals']))],
          if (strList(legit['concerns']).isNotEmpty) ...[Text('Concerns', style: context.text.titleSmall), bullets(strList(legit['concerns']))],
          kv('Notes', str(legit['notes'])),
        ]),
        if (r.answers.isNotEmpty) ...[
          const SizedBox(height: 8),
          section('H', 'Draft application answers', [
            for (final a in r.answers)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(str(a['question']), style: context.text.titleSmall),
                  SelectableText(str(a['draft'])),
                ]),
              ),
          ]),
        ],
        if (r.confidenceGaps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('What could change this', style: context.text.titleSmall),
          const SizedBox(height: 6),
          bullets(r.confidenceGaps),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Evaluated ${DateFormat.yMMMd().format(evaluation.createdAt)} by ${evaluation.model}. A score is not a hiring prediction.',
                style: context.text.bodySmall?.copyWith(color: muted),
              ),
            ),
            if (evaluation.aiRunId != null)
              TextButton.icon(
                onPressed: () => reportAiResponse(context, ref, evaluation.aiRunId!),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Report'),
              ),
          ],
        ),
      ],
    );
  }
}
