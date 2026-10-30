import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'journalist_service.dart';

/// Shows journalist answers delivered privately to this user for information
/// gaps they asked about and chose to be notified on.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _service = JournalistService();
  late Future<List<JournalistNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.myNotifications();
  }

  void _reload() {
    setState(() => _future = _service.myNotifications());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your updates')),
      body: FutureBuilder<List<JournalistNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.error_outline_rounded,
              text: 'Could not load your updates right now.',
              onRetry: _reload,
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const _Message(
              icon: Icons.mark_email_unread_rounded,
              text:
                  'No journalist answers yet. When you save a question for review '
                  'and choose "Notify me", published answers appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _NotificationCard(item: items[index], service: _service),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.service});

  final JournalistNotification item;
  final JournalistService service;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.read
                      ? Icons.mark_email_read_rounded
                      : Icons.fiber_new_rounded,
                  color: const Color(0xFF5D36E8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.originalQuestion,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.answerText),
            if (item.sourceTitle != null && item.sourceTitle!.isNotEmpty) ...[
              const SizedBox(height: 10),
              ActionChip(
                avatar: const Icon(Icons.link_rounded, size: 16),
                label: Text(item.sourceTitle!, overflow: TextOverflow.ellipsis),
                onPressed: item.sourceUrl == null
                    ? null
                    : () async {
                        final uri = Uri.tryParse(item.sourceUrl!);
                        if (uri != null) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
              ),
            ],
            if (!item.read) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => service.markRead(item.notificationId),
                  child: const Text('Mark as read'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF5D36E8)),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
