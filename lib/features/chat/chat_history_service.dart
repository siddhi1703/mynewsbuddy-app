import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_service.dart';

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime? updatedAt;

  factory ChatConversation.fromMap(Map<String, dynamic> map) {
    return ChatConversation(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? 'Chat',
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? ''),
    );
  }
}

/// Per-user chat history, info-gap logging, and notification preference, stored
/// in Supabase (tables chat_conversations, chat_messages, unanswered_questions).
/// Row-level security scopes every row to the signed-in user, so no user id is
/// sent from the client — the database fills it from the auth token.
class ChatHistoryService {
  SupabaseClient get _db => Supabase.instance.client;

  bool get isSignedIn => _db.auth.currentSession != null;

  Future<List<ChatConversation>> conversations() async {
    final rows = await _db
        .from('chat_conversations')
        .select('id,title,updated_at')
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((row) => ChatConversation.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessage>> messages(String conversationId) async {
    final rows = await _db
        .from('chat_messages')
        .select('role,content,answer_state,source_title,source_url,created_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    return (rows as List).map((row) {
      final map = row as Map<String, dynamic>;
      if (map['role'] == 'user') {
        return ChatMessage.user(map['content'] as String? ?? '');
      }
      final title = map['source_title'] as String?;
      final url = map['source_url'] as String?;
      return ChatMessage.assistant(
        text: map['content'] as String? ?? '',
        status: _statusFromState(map['answer_state'] as String?),
        citations: (title != null && title.isNotEmpty)
            ? [Citation(title, url)]
            : const [],
      );
    }).toList();
  }

  /// Saves the user's message, creating a conversation when needed, and returns
  /// the conversation id to use for the matching assistant reply.
  Future<String> saveUserMessage(String? conversationId, String question) async {
    var id = conversationId;
    if (id == null) {
      final created = await _db
          .from('chat_conversations')
          .insert({'title': _titleFrom(question)})
          .select('id')
          .single();
      id = created['id'] as String;
    }
    await _db.from('chat_messages').insert({
      'conversation_id': id,
      'role': 'user',
      'content': question,
    });
    return id;
  }

  Future<void> saveAssistantMessage(
    String conversationId,
    ChatMessage reply,
  ) async {
    final citation = reply.citations.isNotEmpty ? reply.citations.first : null;
    await _db.from('chat_messages').insert({
      'conversation_id': conversationId,
      'role': 'assistant',
      'content': reply.text,
      'answer_state': _stateFromStatus(reply.status),
      'source_title': citation?.title,
      'source_url': citation?.url,
    });
  }

  Future<void> deleteConversation(String id) async {
    await _db.from('chat_conversations').delete().eq('id', id);
  }

  /// Logs a backend-confirmed information gap for journalist review.
  Future<void> logInformationGap({
    required String question,
    required String location,
    required bool notify,
  }) async {
    await _db.from('unanswered_questions').insert({
      'question': question,
      'location': location,
      'notification_requested': notify,
    });
  }

  // Only persist durable answer states; transient errors (auth/rate/system) are
  // not written to history.
  static String? _stateFromStatus(String? status) {
    switch (status) {
      case 'answered':
        return 'cited';
      case 'abstained':
        return 'abstained';
      case 'out_of_scope':
        return 'out_of_scope';
      case 'source_unavailable':
        return 'service_unavailable';
      default:
        return null;
    }
  }

  static String? _statusFromState(String? state) {
    switch (state) {
      case 'cited':
        return 'answered';
      case 'abstained':
        return 'abstained';
      case 'out_of_scope':
        return 'out_of_scope';
      case 'service_unavailable':
        return 'source_unavailable';
      default:
        return null;
    }
  }

  static bool shouldPersist(ChatMessage reply) {
    return reply.status == null ||
        const {
          'answered',
          'abstained',
          'out_of_scope',
          'source_unavailable',
          'conversational',
          'needs_clarification',
        }.contains(reply.status);
  }

  static String _titleFrom(String question) {
    final single = question.replaceAll('\n', ' ').trim();
    if (single.length <= 56) return single.isEmpty ? 'New chat' : single;
    return '${single.substring(0, 55).trim()}…';
  }
}
