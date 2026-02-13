import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:burrow_app/src/rust/frb_generated.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/screens/onboarding_screen.dart';
import 'package:burrow_app/screens/create_identity_screen.dart';
import 'package:burrow_app/screens/import_identity_screen.dart';
import 'package:burrow_app/screens/home_screen.dart';
import 'package:burrow_app/screens/profile_screen.dart';
import 'package:burrow_app/screens/create_group_screen.dart';
import 'package:burrow_app/screens/invite_members_screen.dart';
import 'package:burrow_app/screens/pending_invites_screen.dart';
import 'package:burrow_app/screens/group_info_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ProviderScope(child: BurrowApp()));
}

class BurrowApp extends ConsumerWidget {
  const BurrowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(isLoggedInProvider);

    final router = GoRouter(
      initialLocation: loggedIn ? '/home' : '/onboarding',
      redirect: (context, state) {
        final path = state.uri.path;
        final authPaths = ['/onboarding', '/create-identity', '/import-identity'];
        if (!loggedIn && !authPaths.contains(path)) {
          return '/onboarding';
        }
        if (loggedIn && path == '/onboarding') {
          return '/home';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/create-identity',
          builder: (context, state) => const CreateIdentityScreen(),
        ),
        GoRoute(
          path: '/import-identity',
          builder: (context, state) => const ImportIdentityScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/create-group',
          builder: (context, state) => const CreateGroupScreen(),
        ),
        GoRoute(
          path: '/invite/:groupId',
          builder: (context, state) => InviteMembersScreen(
            groupId: state.pathParameters['groupId']!,
          ),
        ),
        GoRoute(
          path: '/invites',
          builder: (context, state) => const PendingInvitesScreen(),
        ),
        GoRoute(
          path: '/group-info/:groupId',
          builder: (context, state) => GroupInfoScreen(
            groupId: state.pathParameters['groupId']!,
          ),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Burrow',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.brown,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
