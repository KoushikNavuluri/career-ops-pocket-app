import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../features/assistant/assistant_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/cv/cv_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/jobs/explore_screen.dart';
import '../features/jobs/job_detail_screen.dart';
import '../features/jobs/pipeline_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/stories/stories_screen.dart';
import '../features/studio/studio_screen.dart';
import '../features/studio/writing_tool_screen.dart';
import '../features/today/today_screen.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider.select((s) => s.status), (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider).status;
      final loc = state.matchedLocation;
      if (status == AuthStatus.unknown) return loc == '/splash' ? null : '/splash';
      if (status == AuthStatus.signedOut) return loc == '/sign-in' ? null : '/sign-in';
      if (loc == '/sign-in') return '/splash';
      return null;
    },
    errorBuilder: (context, state) => const _NotFoundScreen(),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/today', builder: (_, __) => const TodayScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/explore', builder: (_, __) => const ExploreScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/pipeline', builder: (_, __) => const PipelineScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/studio', builder: (_, __) => const StudioScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/you', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
      GoRoute(
        path: '/job/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => JobDetailScreen(jobId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/cv', parentNavigatorKey: _rootKey, builder: (_, __) => const CvScreen()),
      GoRoute(
        path: '/assistant',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => AssistantScreen(initialJobId: state.uri.queryParameters['jobId']),
      ),
      GoRoute(path: '/stories', parentNavigatorKey: _rootKey, builder: (_, __) => const StoriesScreen()),
      GoRoute(path: '/documents', parentNavigatorKey: _rootKey, builder: (_, __) => const DocumentsScreen()),
      GoRoute(
        path: '/documents/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => DocumentScreen(documentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tools/:feature',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => WritingToolScreen(feature: state.pathParameters['feature']!, initialJobId: state.uri.queryParameters['jobId']),
      ),
    ],
  );
});

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('That page doesn\'t exist.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go('/today'), child: const Text('Back to Today')),
          ],
        ),
      ),
    );
  }
}
