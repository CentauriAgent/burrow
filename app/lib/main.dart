import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:burrow_app/src/rust/frb_generated.dart';
import 'package:burrow_app/src/rust/api/state.dart' as rust_state;
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/screens/onboarding_screen.dart';
import 'package:burrow_app/screens/create_identity_screen.dart';
import 'package:burrow_app/screens/import_identity_screen.dart';
import 'package:burrow_app/screens/chat_shell_screen.dart';
import 'package:burrow_app/screens/profile_screen.dart';
import 'package:burrow_app/screens/create_group_screen.dart';
import 'package:burrow_app/screens/invite_members_screen.dart';
import 'package:burrow_app/screens/pending_invites_screen.dart';
import 'package:burrow_app/screens/group_info_screen.dart';
import 'package:burrow_app/screens/incoming_call_screen.dart';
import 'package:burrow_app/screens/outgoing_call_screen.dart';
import 'package:burrow_app/screens/in_call_screen.dart';
import 'package:burrow_app/providers/call_provider.dart';
import 'package:burrow_app/providers/messages_provider.dart';
import 'package:burrow_app/screens/transcript_screen.dart';
import 'package:burrow_app/screens/meeting_summary_screen.dart';
import 'package:burrow_app/screens/transcript_history_screen.dart';
import 'package:burrow_app/screens/new_dm_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  // Set the data directory for persistent MLS storage before auth loads
  final appDir = await getApplicationSupportDirectory();
  rust_state.setDataDir(path: appDir.path);
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
        final authPaths = [
          '/onboarding',
          '/create-identity',
          '/import-identity',
        ];
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
          builder: (context, state) => const ChatShellScreen(),
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
          builder: (context, state) =>
              InviteMembersScreen(groupId: state.pathParameters['groupId']!),
        ),
        GoRoute(
          path: '/invites',
          builder: (context, state) => const PendingInvitesScreen(),
        ),
        GoRoute(
          path: '/group-info/:groupId',
          builder: (context, state) =>
              GroupInfoScreen(groupId: state.pathParameters['groupId']!),
        ),
        GoRoute(
          path: '/new-dm',
          builder: (context, state) => const NewDmScreen(),
        ),
        GoRoute(
          path: '/chat/:groupId',
          builder: (context, state) =>
              ChatShellScreen(initialGroupId: state.pathParameters['groupId']!),
        ),
        GoRoute(
          path: '/transcript',
          builder: (context, state) => const TranscriptScreen(),
        ),
        GoRoute(
          path: '/meeting-summary/:meetingId',
          builder: (context, state) => MeetingSummaryScreen(
            meetingId: state.pathParameters['meetingId']!,
          ),
        ),
        GoRoute(
          path: '/meeting-history',
          builder: (context, state) => const TranscriptHistoryScreen(),
        ),
      ],
    );

    final callState = ref.watch(callProvider);

    // Start the global message listener when logged in
    if (loggedIn) {
      ref.read(messageListenerProvider).start();
    }

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
      builder: (context, child) {
        // Overlay call screens on top of the app
        return Stack(
          children: [
            child!,
            if (callState.status == CallStatus.incoming)
              const IncomingCallScreen(),
            if (callState.status == CallStatus.outgoing)
              const OutgoingCallScreen(),
            if (callState.status == CallStatus.connecting ||
                callState.status == CallStatus.active ||
                callState.status == CallStatus.ending ||
                callState.status == CallStatus.ended ||
                callState.status == CallStatus.failed)
              const InCallScreen(),
          ],
        );
      },
    );
  }
}
