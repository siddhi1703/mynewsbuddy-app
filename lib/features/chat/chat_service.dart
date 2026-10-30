import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_config.dart';

/// A single chat turn shown in the UI.
class ChatMessage {
  ChatMessage.user(this.text)
    : role = 'user',
      status = null,
      citations = const [],
      savedForJournalist = false,
      location = null;

  ChatMessage.assistant({
    required this.text,
    this.status,
    this.citations = const [],
    this.savedForJournalist = false,
    this.location,
  }) : role = 'assistant';

  final String role; // 'user' | 'assistant'
  final String text;
  final String? status; // answered, abstained, out_of_scope, ...
  final List<Citation> citations;
  final bool savedForJournalist;
  final String? location; // resolved location, used when logging a gap
}

class Citation {
  const Citation(this.title, this.url);
  final String title;
  final String? url;
}

class _RouteResult {
  const _RouteResult({
    required this.sources,
    required this.location,
    required this.needsClarification,
    required this.clarificationQuestion,
    required this.outOfScope,
  });

  final List<String> sources;
  final String? location;
  final bool needsClarification;
  final String? clarificationQuestion;
  final bool outOfScope;
}

class _SourceResult {
  const _SourceResult({required this.evidence, required this.status});
  final List<Map<String, dynamic>> evidence;
  final String status; // succeeded | failed | not_connected
}

/// Orchestrates the grounded RAG flow against the shared FastAPI backend:
/// `/route` to pick trusted sources, client-side retrieval of live evidence
/// (weather + MBTA alerts), then `/ask` for a grounded, cited answer. Sources
/// that are not wired on this client are reported as `not_connected` so the
/// backend returns an honest "source unavailable" rather than guessing.
class ChatService {
  static const _bostonLat = '42.3601';
  static const _bostonLon = '-71.0589';
  static const _nwsHeaders = {
    'User-Agent': 'MyNewsBuddyFlutter/1.0 (student research prototype)',
    'Accept': 'application/geo+json, application/json',
  };

  Future<ChatMessage> send(String question, List<ChatMessage> history) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      return ChatMessage.assistant(
        text: 'Please sign in to use the AI companion.',
        status: 'needs_auth',
      );
    }

    final route = await _route(question, history, token);
    if (route == null) {
      return ChatMessage.assistant(
        text: "I couldn't reach the routing service. Please try again.",
        status: 'system',
      );
    }
    if (route.outOfScope) {
      return ChatMessage.assistant(
        text:
            "That's outside what I can help with — I focus on local Boston "
            'weather, transit, and civic information.',
        status: 'out_of_scope',
      );
    }
    if (route.needsClarification) {
      return ChatMessage.assistant(
        text:
            route.clarificationQuestion ??
            'Could you add a bit more detail so I can find the right source?',
        status: 'needs_clarification',
      );
    }

    final evidence = <Map<String, dynamic>>[];
    final attempts = <Map<String, dynamic>>[];
    for (final source in route.sources) {
      final result = switch (source) {
        'nws' => await _retrieveWeather(),
        'mbta_alerts' => await _retrieveMbtaAlerts(),
        // Predictions, 311, local news, and university events are not wired on
        // this client yet; report them honestly so the backend does not guess.
        _ => const _SourceResult(evidence: [], status: 'not_connected'),
      };
      evidence.addAll(result.evidence);
      attempts.add({
        'source_id': source,
        'status': result.status,
        'evidence_count': result.evidence.length,
      });
    }

    return await _ask(
      question: question,
      location: route.location,
      evidence: evidence,
      attempts: attempts,
      requiredSources: route.sources,
      history: history,
      token: token,
    );
  }

  Future<_RouteResult?> _route(
    String question,
    List<ChatMessage> history,
    String token,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/route'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'question': question,
              'history': _historyPayload(history),
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _RouteResult(
        sources: ((json['sources'] as List?) ?? []).cast<String>(),
        location: json['location'] as String?,
        needsClarification: json['needs_clarification'] == true,
        clarificationQuestion: json['clarification_question'] as String?,
        outOfScope: json['out_of_scope'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ChatMessage> _ask({
    required String question,
    required String? location,
    required List<Map<String, dynamic>> evidence,
    required List<Map<String, dynamic>> attempts,
    required List<String> requiredSources,
    required List<ChatMessage> history,
    required String token,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/ask'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'question': question,
              'location': location,
              'evidence': evidence,
              'history': _historyPayload(history),
              'required_sources': requiredSources,
              'retrieval_attempts': attempts,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 401) {
        return ChatMessage.assistant(
          text: 'Your session expired. Please sign in again.',
          status: 'needs_auth',
        );
      }
      if (response.statusCode == 429) {
        return ChatMessage.assistant(
          text:
              "You're sending questions quickly. Please wait a moment and try "
              'again.',
          status: 'rate_limited',
        );
      }
      if (response.statusCode != 200) {
        return ChatMessage.assistant(
          text:
              "I couldn't complete that request right now (service error). "
              'This is a system issue, not a missing community answer.',
          status: 'system',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final citations = ((json['citations'] as List?) ?? [])
          .map((item) {
            final map = item as Map<String, dynamic>;
            return Citation(
              (map['title'] as String?) ?? 'Source',
              map['url'] as String?,
            );
          })
          .toList();
      return ChatMessage.assistant(
        text: (json['answer'] as String?)?.trim().isNotEmpty == true
            ? (json['answer'] as String).trim()
            : "I don't have a grounded answer for that yet.",
        status: json['status'] as String?,
        citations: citations,
        savedForJournalist: json['save_for_journalist'] == true,
        location: location,
      );
    } catch (_) {
      return ChatMessage.assistant(
        text:
            "I couldn't reach the AI service right now. Please try again in a "
            'moment.',
        status: 'system',
      );
    }
  }

  // Keep recent turns as conversation context. The backend validates history
  // (<=20 items, each 1..8000 chars), so drop empties, truncate long content,
  // and send only the most recent 20.
  List<Map<String, String>> _historyPayload(List<ChatMessage> history) {
    final cleaned = history
        .where((message) => message.text.trim().isNotEmpty)
        .map(
          (message) => {
            'role': message.role,
            'content': message.text.length > 8000
                ? message.text.substring(0, 8000)
                : message.text,
          },
        )
        .toList();
    return cleaned.length > 20
        ? cleaned.sublist(cleaned.length - 20)
        : cleaned;
  }

  Future<_SourceResult> _retrieveWeather() async {
    try {
      final point = await _getJson(
        'https://api.weather.gov/points/$_bostonLat,$_bostonLon',
      );
      if (point == null) return const _SourceResult(evidence: [], status: 'failed');
      final properties = point['properties'] as Map<String, dynamic>?;
      final forecastUrl = properties?['forecast'] as String?;
      final stationsUrl = properties?['observationStations'] as String?;
      final evidence = <Map<String, dynamic>>[];

      if (stationsUrl != null) {
        final stations = await _getJson(stationsUrl);
        final features = stations?['features'] as List<dynamic>?;
        final stationId = (features != null && features.isNotEmpty)
            ? (features.first as Map<String, dynamic>)['id'] as String?
            : null;
        if (stationId != null) {
          final observation = await _getJson('$stationId/observations/latest');
          final props = observation?['properties'] as Map<String, dynamic>?;
          if (props != null) {
            final tempC = (props['temperature'] as Map<String, dynamic>?)?['value'] as num?;
            final windKmh = (props['windSpeed'] as Map<String, dynamic>?)?['value'] as num?;
            final description = props['textDescription'] as String?;
            final timestamp = props['timestamp'] as String?;
            final tempF = tempC == null ? null : (tempC * 9 / 5 + 32).round();
            final windMph = windKmh == null ? null : (windKmh * 0.621371).round();
            evidence.add({
              'source_id': 'nws-observation',
              'title': 'Latest station observation (Boston, MA)',
              'url': stationId,
              'text':
                  'Latest station observation'
                  '${timestamp != null ? ' as of $timestamp' : ''}: '
                  '${tempF != null ? '$tempF°F' : 'temperature unavailable'}, '
                  '${description ?? 'conditions unavailable'}'
                  '${windMph != null ? ', wind $windMph mph' : ''}.',
            });
          }
        }
      }

      if (forecastUrl != null) {
        final forecast = await _getJson(forecastUrl);
        final periods =
            (forecast?['properties'] as Map<String, dynamic>?)?['periods']
                as List<dynamic>?;
        if (periods != null && periods.isNotEmpty) {
          final text = periods
              .take(4)
              .map((period) {
                final map = period as Map<String, dynamic>;
                return '${map['name']}: ${map['detailedForecast']}';
              })
              .join(' ');
          evidence.add({
            'source_id': 'nws-forecast',
            'title': 'NWS forecast (Boston, MA)',
            'url': forecastUrl,
            'text': text,
          });
        }
      }

      return _SourceResult(
        evidence: evidence,
        status: evidence.isEmpty ? 'failed' : 'succeeded',
      );
    } catch (_) {
      return const _SourceResult(evidence: [], status: 'failed');
    }
  }

  Future<_SourceResult> _retrieveMbtaAlerts() async {
    try {
      final payload = await _getJson(
        'https://api-v3.mbta.com/alerts?filter%5Broute_type%5D=0,1',
      );
      if (payload == null) {
        return const _SourceResult(evidence: [], status: 'failed');
      }
      final alerts = (payload['data'] as List<dynamic>?) ?? [];
      final now = DateTime.now();
      final evidence = <Map<String, dynamic>>[];

      for (final alert in alerts) {
        final map = alert as Map<String, dynamic>;
        final attributes = map['attributes'] as Map<String, dynamic>?;
        if (attributes == null) continue;
        final periods = attributes['active_period'] as List<dynamic>? ?? [];
        final isActive = periods.any((period) {
          final value = period as Map<String, dynamic>;
          final start = DateTime.tryParse(value['start'] as String? ?? '');
          final end = DateTime.tryParse(value['end'] as String? ?? '');
          return (start == null || !now.isBefore(start)) &&
              (end == null || now.isBefore(end));
        });
        if (!isActive) continue;

        final header = attributes['header'] as String?;
        final effect = attributes['service_effect'] as String?;
        final url = attributes['url'] as String?;
        evidence.add({
          'source_id': 'mbta-alerts-${map['id']}',
          'title': effect ?? 'MBTA service alert',
          'url': (url != null && url.startsWith('http'))
              ? url
              : 'https://www.mbta.com/alerts',
          'text': header ?? effect ?? 'Active MBTA alert.',
        });
        if (evidence.length >= 8) break;
      }

      if (evidence.isEmpty) {
        // Provide explicit "no active alert" evidence so the model can say so
        // without claiming all service is normal.
        evidence.add({
          'source_id': 'mbta-alerts-none',
          'title': 'MBTA subway alerts',
          'url': 'https://www.mbta.com/alerts',
          'text':
              'No active MBTA subway (light/heavy rail) alerts are currently '
              'published by the official MBTA V3 API.',
        });
      }

      return _SourceResult(evidence: evidence, status: 'succeeded');
    } catch (_) {
      return const _SourceResult(evidence: [], status: 'failed');
    }
  }

  Future<Map<String, dynamic>?> _getJson(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: _nwsHeaders)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
