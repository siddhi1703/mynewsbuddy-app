import 'package:supabase_flutter/supabase_flutter.dart';

class GapCluster {
  const GapCluster({
    required this.clusterId,
    required this.representativeQuestion,
    required this.category,
    required this.status,
    required this.questionCount,
    required this.uniqueAskerCount,
    required this.locations,
    required this.questionExamples,
  });

  final String clusterId;
  final String representativeQuestion;
  final String category;
  final String status;
  final int questionCount;
  final int uniqueAskerCount;
  final List<String> locations;
  final List<String> questionExamples;

  factory GapCluster.fromMap(Map<String, dynamic> map) {
    return GapCluster(
      clusterId: map['cluster_id'] as String,
      representativeQuestion:
          (map['representative_question'] as String?) ?? 'Community question',
      category: (map['category'] as String?) ?? 'pending_review',
      status: (map['status'] as String?) ?? 'candidate',
      questionCount: (map['question_count'] as num?)?.toInt() ?? 0,
      uniqueAskerCount: (map['unique_asker_count'] as num?)?.toInt() ?? 0,
      locations: ((map['locations'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      questionExamples: ((map['question_examples'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class GapSummary {
  const GapSummary({
    required this.topicCount,
    required this.questionCount,
    required this.uniqueAskerCount,
  });

  final int topicCount;
  final int questionCount;
  final int uniqueAskerCount;

  factory GapSummary.fromMap(Map<String, dynamic> map) {
    return GapSummary(
      topicCount: (map['topic_count'] as num?)?.toInt() ?? 0,
      questionCount: (map['question_count'] as num?)?.toInt() ?? 0,
      uniqueAskerCount: (map['unique_asker_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class JournalistNotification {
  const JournalistNotification({
    required this.notificationId,
    required this.originalQuestion,
    required this.answerText,
    required this.sourceTitle,
    required this.sourceUrl,
    required this.read,
  });

  final String notificationId;
  final String originalQuestion;
  final String answerText;
  final String? sourceTitle;
  final String? sourceUrl;
  final bool read;

  factory JournalistNotification.fromMap(Map<String, dynamic> map) {
    return JournalistNotification(
      notificationId: map['notification_id'] as String,
      originalQuestion:
          (map['original_question'] as String?) ?? 'Your question',
      answerText: (map['answer_text'] as String?) ?? '',
      sourceTitle: map['source_title'] as String?,
      sourceUrl: map['source_url'] as String?,
      read: map['read_at'] != null,
    );
  }
}

/// Reads the journalist inbox (aggregate clusters) and per-user response
/// notifications through the server-side RPCs. Cluster access is enforced by the
/// database (`is_journalist()`), so this is safe even though the UI also gates on
/// the user's role claim.
class JournalistService {
  SupabaseClient get _db => Supabase.instance.client;

  /// Role is a protected app_metadata claim the user cannot change themselves.
  bool get isJournalist {
    final role = _db.auth.currentUser?.appMetadata['role'];
    return role == 'journalist' || role == 'editor' || role == 'admin';
  }

  Future<GapSummary?> summary() async {
    final result = await _db.rpc('get_information_gap_summary');
    if (result is Map) {
      return GapSummary.fromMap(Map<String, dynamic>.from(result));
    }
    return null;
  }

  Future<List<GapCluster>> clusters() async {
    final result = await _db.rpc(
      'get_information_gap_clusters',
      params: {'minimum_questions': 1},
    );
    return (result as List)
        .map((row) => GapCluster.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<JournalistNotification>> myNotifications() async {
    final result = await _db.rpc('get_my_journalist_notifications');
    return (result as List)
        .map(
          (row) =>
              JournalistNotification.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> markRead(String notificationId) async {
    await _db.rpc(
      'mark_journalist_notification_read',
      params: {'target_notification_id': notificationId},
    );
  }
}
