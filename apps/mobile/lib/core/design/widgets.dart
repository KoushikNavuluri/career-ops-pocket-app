import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'theme.dart';
import 'tokens.dart';

/// Uppercase mono label, e.g. "YOUR SEARCH, IN FOCUS".
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTheme.mono(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: color ?? context.pocket.mutedForeground)),
    );
  }
}

/// The career/ops. wordmark.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 29});
  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    final style = AppTheme.display(TextStyle(fontSize: size, letterSpacing: -size * 0.037, height: 1, color: context.colors.onSurface));
    return Semantics(
      label: 'Career Ops',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(angle: 15 * math.pi / 180, child: Icon(Icons.emergency, color: primary, size: size * 0.8)),
          SizedBox(width: size * 0.2),
          Text('career', style: style),
          Text('/', style: AppTheme.sans(TextStyle(fontSize: size * 0.75, color: Palette.brandDash, height: 1))),
          Text('ops', style: style),
          Text('.', style: style.copyWith(color: primary)),
        ],
      ),
    );
  }
}

class PocketCard extends StatelessWidget {
  const PocketCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(18), this.color});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(Radii.chip)),
      child: Text(status, style: context.text.labelMedium?.copyWith(color: c.fg, fontWeight: FontWeight.w500)),
    );
  }
}

class ScoreBadge extends StatelessWidget {
  const ScoreBadge(this.score, {super.key, this.large = false});
  final double? score;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final p = context.pocket;
    if (s == null) {
      return Text('Not scored', style: context.text.bodySmall?.copyWith(color: p.mutedForeground));
    }
    final low = s < 4;
    return Semantics(
      label: 'Fit score ${s.toStringAsFixed(1)} out of 5',
      excludeSemantics: true,
      child: Container(
        padding: large ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12) : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: low ? p.peach : p.sage, borderRadius: BorderRadius.circular(large ? 13 : Radii.chip)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              s.toStringAsFixed(1),
              style: AppTheme.sans(TextStyle(fontSize: large ? 31 : 14, fontWeight: FontWeight.w700, color: low ? p.lowScoreText : p.scoreText, height: 1.1)),
            ),
            const SizedBox(width: 4),
            Text('/5', style: context.text.bodySmall?.copyWith(color: p.mutedForeground)),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.titleLarge)),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: context.colors.primary),
            const SizedBox(height: 14),
            Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: context.text.bodyMedium?.copyWith(color: context.pocket.mutedForeground), textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'That didn\'t load',
      message: friendlyError(error),
      actionLabel: onRetry == null ? null : 'Retry',
      onAction: onRetry,
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[const SizedBox(height: 14), Text(label!, style: context.text.bodyMedium)],
        ],
      ),
    );
  }
}

/// Placeholder rows while a list loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 4});
  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = context.pocket.muted;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows,
      physics: const NeverScrollableScrollPhysics(),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(height: 86, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(Radii.card))),
    );
  }
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.icon = Icons.info_outline});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.pocket.sage, borderRadius: BorderRadius.circular(Radii.card)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.pocket.scoreText),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.text.bodySmall)),
        ],
      ),
    );
  }
}

/// Constrains content width on tablets and desktop so cards don't stretch.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 860});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
