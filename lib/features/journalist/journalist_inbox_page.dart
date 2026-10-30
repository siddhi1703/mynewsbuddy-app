import 'package:flutter/material.dart';

import 'journalist_service.dart';

/// Role-protected aggregate view of clustered information gaps for approved
/// journalists. The database RPCs enforce access; this page also shows a clear
/// message if a non-journalist reaches it.
class JournalistInboxPage extends StatefulWidget {
  const JournalistInboxPage({super.key});

  @override
  State<JournalistInboxPage> createState() => _JournalistInboxPageState();
}

class _JournalistInboxPageState extends State<JournalistInboxPage> {
  final _service = JournalistService();
  late Future<_InboxData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_InboxData> _load() async {
    final summary = await _service.summary();
    final clusters = await _service.clusters();
    return _InboxData(summary: summary, clusters: clusters);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journalist Inbox')),
      body: FutureBuilder<_InboxData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.lock_outline_rounded,
              text:
                  'This inbox is available to approved journalist accounts only. '
                  'If you are approved, sign out and back in so your role loads.',
              onRetry: _reload,
            );
          }
          final data = snapshot.data!;
          final clusters = data.clusters;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (data.summary != null) _SummaryRow(summary: data.summary!),
                const SizedBox(height: 16),
                Text(
                  'Reporting leads',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (clusters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No active information-gap clusters yet. Genuine unanswered '
                      'community questions will group here for review.',
                    ),
                  )
                else
                  for (final cluster in clusters) _ClusterCard(cluster: cluster),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InboxData {
  const _InboxData({required this.summary, required this.clusters});
  final GapSummary? summary;
  final List<GapCluster> clusters;
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});
  final GapSummary summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Stat(label: 'Topics', value: summary.topicCount),
        const SizedBox(width: 10),
        _Stat(label: 'Questions', value: summary.questionCount),
        const SizedBox(width: 10),
        _Stat(label: 'People', value: summary.uniqueAskerCount),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF5D36E8).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5D36E8),
              ),
            ),
            Text(label, style: const TextStyle(color: Color(0xFF60719B))),
          ],
        ),
      ),
    );
  }
}

class _ClusterCard extends StatelessWidget {
  const _ClusterCard({required this.cluster});
  final GapCluster cluster;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cluster.representativeQuestion,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Tag('${cluster.questionCount} asks'),
                _Tag('${cluster.uniqueAskerCount} people'),
                _Tag(cluster.category.replaceAll('_', ' ')),
                if (cluster.locations.isNotEmpty) _Tag(cluster.locations.first),
              ],
            ),
            if (cluster.questionExamples.length > 1) ...[
              const SizedBox(height: 10),
              const Text(
                'Examples',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF60719B),
                ),
              ),
              const SizedBox(height: 4),
              for (final example in cluster.questionExamples.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('• $example'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF5D36E8).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5D36E8),
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
