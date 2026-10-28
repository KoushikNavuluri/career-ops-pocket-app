import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';

/// Email + password sign-in through Microsoft Entra External ID (system browser, PKCE).
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final configured = AppConfig.isAuthConfigured;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandMark(size: 34),
                  const SizedBox(height: 40),
                  const Eyebrow('Your career workspace'),
                  const SizedBox(height: 10),
                  Text('Welcome back.', style: context.text.displayLarge),
                  const SizedBox(height: 12),
                  Text(
                    'Set your direction, keep your evidence in one place and decide every move yourself.',
                    style: context.text.bodyLarge?.copyWith(color: context.pocket.mutedForeground),
                  ),
                  const SizedBox(height: 32),
                  if (!configured)
                    const Notice(
                      'Sign-in isn\'t configured for this build. The deployment owner needs to supply AUTH_DISCOVERY_URL, '
                      'AUTH_CLIENT_ID and AUTH_API_SCOPE (see docs/SETUP-AZURE.md).',
                      icon: Icons.settings_outlined,
                    ),
                  if (auth.error != null) ...[
                    Text(auth.error!, style: context.text.bodyMedium?.copyWith(color: context.colors.error)),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: !configured || auth.busy ? null : () => controller.signIn(),
                      child: auth.busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sign in with email'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: !configured || auth.busy ? null : () => controller.signIn(createAccount: true),
                      child: const Text('Create a new account'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'You\'ll sign in on a secure Microsoft-hosted page with your email and password. '
                    'Forgot your password? Use "Forgot password" on that page.',
                    style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Career Ops never applies, submits or sends anything on your behalf.',
                    style: context.text.bodySmall?.copyWith(color: context.pocket.mutedForeground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
