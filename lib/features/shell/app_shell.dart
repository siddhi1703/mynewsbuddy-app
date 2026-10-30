import 'package:flutter/material.dart';

import '../../core/live_data_service.dart';
import '../chat/chat_page.dart';
import '../journalist/journalist_inbox_page.dart';
import '../journalist/journalist_service.dart';
import '../journalist/notifications_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.displayName,
    required this.onSignOut,
    this.isDemoMode = false,
    super.key,
  });

  final String displayName;
  final VoidCallback onSignOut;
  final bool isDemoMode;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        displayName: widget.displayName,
        isDemoMode: widget.isDemoMode,
        openChat: () => setState(() => _index = 1),
      ),
      ChatPage(isDemoMode: widget.isDemoMode),
      const MigrationPage(
        icon: Icons.map_rounded,
        title: 'Map',
        description:
            'The backup project is ready for a cross-platform map. Route search and live location are intentionally not presented as complete yet.',
      ),
      const MigrationPage(
        icon: Icons.calendar_month_rounded,
        title: 'Events',
        description:
            'Boston Events feeds and the highlighted calendar will be migrated after the authenticated chat path.',
      ),
      ProfilePage(
        displayName: widget.displayName,
        isDemoMode: widget.isDemoMode,
        onSignOut: widget.onSignOut,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.forum_rounded), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.map_rounded), label: 'Map'),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_rounded),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    required this.displayName,
    required this.openChat,
    required this.isDemoMode,
    super.key,
  });

  final String displayName;
  final VoidCallback openChat;
  final bool isDemoMode;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _service = LiveDataService();
  late Future<HomeSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _service.loadBostonSnapshot();
  }

  void _refresh() {
    setState(() => _snapshot = _service.loadBostonSnapshot());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8FCDF4), Color(0xFFD7EFFF), Color(0xFFF4E9FF)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: FutureBuilder<HomeSnapshot>(
          future: _snapshot,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: _Pill(
                          icon: Icons.location_on_rounded,
                          eyebrow: 'BACKUP LOCATION',
                          value: 'Boston, MA',
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Refresh live sources',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _WeatherCard(
                    displayName: widget.displayName,
                    data: data,
                    loading:
                        snapshot.connectionState == ConnectionState.waiting,
                  ),
                  const SizedBox(height: 16),
                  if (widget.isDemoMode) ...[
                    const _DemoBanner(),
                    const SizedBox(height: 12),
                  ],
                  InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: widget.openChat,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 17,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFF5D36E8),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Ask about Boston…',
                              style: TextStyle(
                                fontSize: 17,
                                color: Color(0xFF617096),
                              ),
                            ),
                          ),
                          CircleAvatar(
                            backgroundColor: Color(0xFF5D36E8),
                            foregroundColor: Colors.white,
                            child: Icon(Icons.mic_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuestionChip(
                          icon: Icons.tram_rounded,
                          label: 'Green Line delays?',
                          onTap: widget.openChat,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuestionChip(
                          icon: Icons.lightbulb_rounded,
                          label: 'Streetlight reports?',
                          onTap: widget.openChat,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Important near you',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text('Verified live connections for Boston'),
                  const SizedBox(height: 12),
                  _UpdatePanel(
                    children: [
                      _UpdateRow(
                        icon: Icons.train_rounded,
                        color: Colors.green,
                        title: data?.mbtaAlertCount == null
                            ? 'MBTA temporarily unavailable'
                            : '${data!.mbtaAlertCount} active transit alerts',
                        detail: 'Official MBTA V3 API',
                        badge: data?.mbtaAlertCount == null ? 'RETRY' : 'LIVE',
                      ),
                      _UpdateRow(
                        icon: Icons.smart_toy_rounded,
                        color: const Color(0xFF5D36E8),
                        title: data?.backendOnline == true
                            ? 'AI backend is connected'
                            : 'AI backend is waking or unavailable',
                        detail: 'Render · Gemini grounding service',
                        badge: data?.backendOnline == true ? 'LIVE' : 'CHECK',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Migration roadmap',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  const _UpdatePanel(
                    children: [
                      _UpdateRow(
                        icon: Icons.calendar_month_rounded,
                        color: Colors.purple,
                        title: 'Boston Events',
                        detail: 'Next Flutter data-source migration',
                        badge: 'NEXT',
                      ),
                      _UpdateRow(
                        icon: Icons.construction_rounded,
                        color: Colors.blue,
                        title: 'Boston 311',
                        detail: 'Waiting for API access',
                        badge: 'PLANNED',
                      ),
                      _UpdateRow(
                        icon: Icons.newspaper_rounded,
                        color: Colors.orange,
                        title: 'Journalist Inbox',
                        detail: 'Supabase workflow will be ported after Chat',
                        badge: 'PLANNED',
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.displayName,
    required this.data,
    required this.loading,
  });

  final String displayName;
  final HomeSnapshot? data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF537DBB), Color(0xFF7B75BD)],
        ),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF334B8C).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Tag(label: "TODAY'S HIGHLIGHT"),
            const SizedBox(height: 20),
            Text(
              'Good ${_dayPart()}, $displayName',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 22),
            if (loading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    data?.temperatureF == null
                        ? '—°'
                        : '${data!.temperatureF}°',
                    style: const TextStyle(
                      fontSize: 70,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data?.condition ?? 'Weather.gov unavailable',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          data?.windMph == null
                              ? 'Pull to refresh the live observation'
                              : 'Wind ${data!.windMph} mph',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Image.asset(
                    _mascotAsset(data?.condition),
                    width: 78,
                    height: 78,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Icon(Icons.verified_rounded, size: 18),
                const SizedBox(width: 7),
                Text(
                  data?.temperatureF == null
                      ? 'Weather.gov · not connected'
                      : 'Weather.gov · live observation',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _dayPart() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  // Pick the weather companion mascot from the current condition and time.
  static String _mascotAsset(String? condition) {
    final hour = DateTime.now().hour;
    final isNight = hour < 6 || hour >= 20;
    final c = (condition ?? '').toLowerCase();
    if (c.contains('thunder') || c.contains('storm')) {
      return 'assets/images/WeatherMascotStormy.png';
    }
    if (c.contains('snow') ||
        c.contains('sleet') ||
        c.contains('ice') ||
        c.contains('flurr')) {
      return 'assets/images/WeatherMascotSnowy.png';
    }
    if (c.contains('rain') || c.contains('shower') || c.contains('drizzle')) {
      return 'assets/images/WeatherMascotRainy.png';
    }
    if (isNight) return 'assets/images/WeatherMascotNight.png';
    if (c.contains('cloud') ||
        c.contains('overcast') ||
        c.contains('fog') ||
        c.contains('haze') ||
        c.contains('mist')) {
      return 'assets/images/WeatherMascotCloudy.png';
    }
    return 'assets/images/WeatherMascotSunny.png';
  }
}

class MigrationPage extends StatelessWidget {
  const MigrationPage({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: const Color(
                    0xFF5D36E8,
                  ).withValues(alpha: 0.12),
                  child: Icon(icon, size: 44, color: const Color(0xFF5D36E8)),
                ),
                const SizedBox(height: 22),
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                Text(description, textAlign: TextAlign.center),
                const SizedBox(height: 22),
                const _Tag(
                  label: 'BACKUP PROJECT · MIGRATION PENDING',
                  dark: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    required this.displayName,
    required this.isDemoMode,
    required this.onSignOut,
    super.key,
  });

  final String displayName;
  final bool isDemoMode;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text('Profile', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    child: Icon(Icons.person_rounded, size: 34),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        isDemoMode ? 'Backup demo account' : 'Supabase account',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!isDemoMode)
            Card(
              child: ListTile(
                leading: const Icon(Icons.mark_email_unread_rounded),
                title: const Text('Your updates'),
                subtitle: const Text(
                  'Journalist answers to questions you saved for review',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsPage(),
                  ),
                ),
              ),
            ),
          if (!isDemoMode && JournalistService().isJournalist) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.assignment_turned_in_rounded),
                title: const Text('Journalist Inbox'),
                subtitle: const Text(
                  'Clustered community information gaps to report on',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const JournalistInboxPage(),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: Text(isDemoMode ? 'Exit demo' : 'Sign out'),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.eyebrow, required this.value});

  final IconData icon;
  final String eyebrow;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF35458A)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: Color(0xFF60719B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF26366F),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.science_rounded, color: Color(0xFF9B6500)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Backup demo mode: live public feeds work, but private Supabase features are disabled.',
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionChip extends StatelessWidget {
  const _QuestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
      backgroundColor: Colors.white.withValues(alpha: 0.48),
    );
  }
}

class _UpdatePanel extends StatelessWidget {
  const _UpdatePanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index < children.length - 1)
              const Divider(height: 1, indent: 72),
          ],
        ],
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.badge,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    _Tag(label: badge, dark: true),
                  ],
                ),
                const SizedBox(height: 3),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.dark = false});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF5D36E8).withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: dark ? const Color(0xFF5D36E8) : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
