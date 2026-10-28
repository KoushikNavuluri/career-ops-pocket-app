import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';

/// Shown while the session restores and the account loads; then routes to onboarding or Today.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;

  void _route(Me me) {
    if (_navigated) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(me.onboarded ? '/today' : '/onboarding');
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(authControllerProvider.select((s) => s.status));
    Widget? below;
    if (status == AuthStatus.signedIn) {
      final me = ref.watch(meProvider);
      me.whenData(_route);
      if (me.hasError && !me.isLoading) {
        below = Column(
          children: [
            Text(friendlyError(me.error!), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => ref.invalidate(meProvider), child: const Text('Retry workspace connection')),
            TextButton(onPressed: () => ref.read(authControllerProvider.notifier).signOut(), child: const Text('Sign out')),
          ],
        );
      }
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 46),
                const SizedBox(height: 16),
                Text('Your next chapter starts here.', style: context.text.titleMedium?.copyWith(color: context.pocket.mutedForeground)),
                const SizedBox(height: 32),
                below ?? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
