import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/auth_page.dart';
import '../features/shell/app_shell.dart';
import 'theme.dart';

class MyNewsBuddyApp extends StatelessWidget {
  const MyNewsBuddyApp({required this.supabaseConfigured, super.key});

  final bool supabaseConfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Companion',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: RootGate(supabaseConfigured: supabaseConfigured),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({required this.supabaseConfigured, super.key});

  final bool supabaseConfigured;

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _demoMode = false;

  @override
  Widget build(BuildContext context) {
    if (_demoMode) {
      return AppShell(
        displayName: 'Siddhi',
        isDemoMode: true,
        onSignOut: () => setState(() => _demoMode = false),
      );
    }

    if (!widget.supabaseConfigured) {
      return AuthPage(
        configurationMessage:
            'Supabase is not configured in this backup build yet.',
        onContinueDemo: () => setState(() => _demoMode = true),
      );
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          return AuthPage(
            onContinueDemo: () => setState(() => _demoMode = true),
          );
        }

        final fullName = session.user.userMetadata?['full_name'] as String?;
        final firstName = fullName?.trim().split(RegExp(r'\s+')).first;
        return AppShell(
          displayName: firstName?.isNotEmpty == true ? firstName! : 'Neighbor',
          onSignOut: () => Supabase.instance.client.auth.signOut(),
        );
      },
    );
  }
}
