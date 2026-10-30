import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_history_service.dart';
import 'chat_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({required this.isDemoMode, super.key});

  final bool isDemoMode;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

ChatMessage _welcomeMessage() => ChatMessage.assistant(
  text:
      "Hi! I'm your Boston local companion. Ask me about the weather or "
      'MBTA subway service, and I\'ll answer from live, trusted sources — '
      "and tell you honestly when I don't have an answer.",
  status: 'conversational',
);

class _ChatPageState extends State<ChatPage> {
  final _service = ChatService();
  final _history = ChatHistoryService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [_welcomeMessage()];
  bool _sending = false;
  String? _conversationId;

  bool get _historyEnabled => !widget.isDemoMode && _history.isSignedIn;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    // History is everything shown so far (before this question).
    final history = List<ChatMessage>.from(_messages);

    setState(() {
      _messages.add(ChatMessage.user(text));
      _sending = true;
      _controller.clear();
    });
    _scrollToEnd();

    // Persist the user turn (creates a conversation on the first message).
    if (_historyEnabled) {
      try {
        _conversationId = await _history.saveUserMessage(_conversationId, text);
      } catch (_) {
        /* history is best-effort; never block the chat */
      }
    }

    final reply = await _service.send(text, history);
    if (!mounted) return;
    setState(() {
      _messages.add(reply);
      _sending = false;
    });
    _scrollToEnd();

    if (_historyEnabled) {
      if (ChatHistoryService.shouldPersist(reply) && _conversationId != null) {
        try {
          await _history.saveAssistantMessage(_conversationId!, reply);
        } catch (_) {}
      }
      // Log a backend-confirmed gap and request notification when a journalist
      // publishes an answer.
      if (reply.savedForJournalist) {
        try {
          await _history.logInformationGap(
            question: text,
            location: reply.location ?? 'Boston, MA',
            notify: true,
          );
        } catch (_) {}
      }
    }
  }

  void _newChat() {
    setState(() {
      _messages
        ..clear()
        ..add(_welcomeMessage());
      _conversationId = null;
    });
  }

  Future<void> _openHistory() async {
    if (!_historyEnabled) return;
    final selected = await showModalBottomSheet<ChatConversation>(
      context: context,
      showDragHandle: true,
      builder: (context) => _HistorySheet(service: _history),
    );
    if (selected == null || !mounted) return;
    try {
      final loaded = await _history.messages(selected.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(loaded.isEmpty ? [_welcomeMessage()] : loaded);
        _conversationId = selected.id;
      });
      _scrollToEnd();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that conversation.')),
        );
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _ChatHeader(
            onNewChat: _newChat,
            onHistory: _historyEnabled ? _openHistory : null,
          ),
          if (widget.isDemoMode) const _DemoNotice(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const _TypingBubble();
                }
                return _MessageBubble(message: _messages[index]);
              },
            ),
          ),
          _Composer(
            controller: _controller,
            enabled: !widget.isDemoMode && !_sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.onNewChat, this.onHistory});

  final VoidCallback onNewChat;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFF5D36E8),
            foregroundColor: Colors.white,
            child: Icon(Icons.auto_awesome_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Local Companion',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Grounded in live weather & MBTA data',
                  style: TextStyle(color: Color(0xFF60719B)),
                ),
              ],
            ),
          ),
          if (onHistory != null)
            IconButton(
              onPressed: onHistory,
              tooltip: 'Chat history',
              icon: const Icon(Icons.history_rounded),
            ),
          IconButton(
            onPressed: onNewChat,
            tooltip: 'New chat',
            icon: const Icon(Icons.edit_square),
          ),
        ],
      ),
    );
  }
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.service});
  final ChatHistoryService service;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late Future<List<ChatConversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.conversations();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Chat history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ChatConversation>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No saved conversations yet.'),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final conversation = items[index];
                    return ListTile(
                      leading: const Icon(Icons.forum_rounded),
                      title: Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          await widget.service
                              .deleteConversation(conversation.id);
                          setState(() {
                            _future = widget.service.conversations();
                          });
                        },
                      ),
                      onTap: () => Navigator.of(context).pop(conversation),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_rounded, color: Color(0xFF9B6500)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sign in to use the AI chat — it needs an authenticated account.',
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    final alignment = _isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = _isUser ? const Color(0xFF5D36E8) : Colors.white;
    final textColor = _isUser ? Colors.white : const Color(0xFF1E2746);

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          boxShadow: _isUser
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF334B8C).withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isUser && _statusLabel(message.status) != null) ...[
              _StatusChip(label: _statusLabel(message.status)!),
              const SizedBox(height: 8),
            ],
            Text(message.text, style: TextStyle(color: textColor, fontSize: 15)),
            if (message.citations.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final citation in message.citations)
                    _CitationChip(citation: citation),
                ],
              ),
            ],
            if (message.savedForJournalist) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(
                    Icons.outbox_rounded,
                    size: 15,
                    color: Color(0xFF60719B),
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Saved as an information gap for journalist review.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF60719B),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String? _statusLabel(String? status) {
    switch (status) {
      case 'abstained':
        return "I don't know yet";
      case 'out_of_scope':
        return 'Out of scope';
      case 'needs_clarification':
        return 'Need a detail';
      case 'source_unavailable':
        return 'Source unavailable';
      case 'answered':
      case 'conversational':
      case null:
        return null;
      default:
        return null;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF5D36E8).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Color(0xFF5D36E8),
        ),
      ),
    );
  }
}

class _CitationChip extends StatelessWidget {
  const _CitationChip({required this.citation});

  final Citation citation;

  Future<void> _open() async {
    final url = citation.url;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: citation.url == null ? null : _open,
      avatar: const Icon(Icons.link_rounded, size: 16),
      label: Text(
        citation.title,
        overflow: TextOverflow.ellipsis,
      ),
      backgroundColor: const Color(0xFFEEE9FF),
      side: BorderSide.none,
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: Colors.white.withValues(alpha: 0.6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: enabled ? 'Ask about Boston…' : 'Sign in to chat',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: enabled ? onSend : null,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF5D36E8),
              padding: const EdgeInsets.all(14),
            ),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
