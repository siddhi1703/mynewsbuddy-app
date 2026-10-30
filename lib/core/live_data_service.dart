import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

class HomeSnapshot {
  const HomeSnapshot({
    required this.temperatureF,
    required this.condition,
    required this.windMph,
    required this.weatherUpdatedAt,
    required this.mbtaAlertCount,
    required this.backendOnline,
    required this.loadedAt,
  });

  final int? temperatureF;
  final String? condition;
  final int? windMph;
  final DateTime? weatherUpdatedAt;
  final int? mbtaAlertCount;
  final bool backendOnline;
  final DateTime loadedAt;
}

class LiveDataService {
  static const _headers = {
    'User-Agent': 'MyNewsBuddyFlutter/1.0 (student research prototype)',
    'Accept': 'application/geo+json, application/json',
  };

  Future<HomeSnapshot> loadBostonSnapshot() async {
    final results = await Future.wait([
      _loadBostonWeather(),
      _loadActiveMbtaAlerts(),
      _checkBackend(),
    ]);
    final weather = results[0] as _WeatherResult?;

    return HomeSnapshot(
      temperatureF: weather?.temperatureF,
      condition: weather?.condition,
      windMph: weather?.windMph,
      weatherUpdatedAt: weather?.updatedAt,
      mbtaAlertCount: results[1] as int?,
      backendOnline: results[2] as bool,
      loadedAt: DateTime.now(),
    );
  }

  Future<_WeatherResult?> _loadBostonWeather() async {
    try {
      final pointResponse = await http
          .get(
            Uri.parse('https://api.weather.gov/points/42.3601,-71.0589'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      if (pointResponse.statusCode != 200) return null;

      final point = jsonDecode(pointResponse.body) as Map<String, dynamic>;
      final stationsUrl =
          (point['properties'] as Map<String, dynamic>)['observationStations']
              as String?;
      if (stationsUrl == null) return null;

      final stationsResponse = await http
          .get(Uri.parse(stationsUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (stationsResponse.statusCode != 200) return null;
      final stations =
          jsonDecode(stationsResponse.body) as Map<String, dynamic>;
      final features = stations['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return null;
      final stationId =
          (features.first as Map<String, dynamic>)['id'] as String?;
      if (stationId == null) return null;

      final observationResponse = await http
          .get(Uri.parse('$stationId/observations/latest'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (observationResponse.statusCode != 200) return null;
      final observation =
          jsonDecode(observationResponse.body) as Map<String, dynamic>;
      final properties = observation['properties'] as Map<String, dynamic>;
      final temperatureC =
          (properties['temperature'] as Map<String, dynamic>)['value'] as num?;
      final windKmh =
          (properties['windSpeed'] as Map<String, dynamic>)['value'] as num?;

      var temperatureF =
          temperatureC == null ? null : (temperatureC * 9 / 5 + 32).round();
      var condition = properties['textDescription'] as String?;

      // The latest station observation sometimes has a null temperature. Fall
      // back to the current forecast period so the card still shows a reading
      // instead of reporting "not connected".
      if (temperatureF == null || condition == null || condition.isEmpty) {
        final fallback = await _loadForecastFallback(point);
        temperatureF ??= fallback?.temperatureF;
        if (condition == null || condition.isEmpty) {
          condition = fallback?.condition;
        }
      }

      return _WeatherResult(
        temperatureF: temperatureF,
        condition: condition,
        windMph: windKmh == null ? null : (windKmh * 0.621371).round(),
        updatedAt: DateTime.tryParse(properties['timestamp'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  Future<_WeatherResult?> _loadForecastFallback(
    Map<String, dynamic> point,
  ) async {
    try {
      final forecastUrl =
          (point['properties'] as Map<String, dynamic>)['forecast'] as String?;
      if (forecastUrl == null) return null;
      final response = await http
          .get(Uri.parse(forecastUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final periods =
          ((jsonDecode(response.body) as Map<String, dynamic>)['properties']
                  as Map<String, dynamic>?)?['periods']
              as List<dynamic>?;
      if (periods == null || periods.isEmpty) return null;
      final current = periods.first as Map<String, dynamic>;
      // Forecast temperature is already in the unit given by temperatureUnit
      // (Fahrenheit for US NWS forecasts).
      return _WeatherResult(
        temperatureF: (current['temperature'] as num?)?.round(),
        condition: current['shortForecast'] as String?,
        windMph: null,
        updatedAt: null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<int?> _loadActiveMbtaAlerts() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://api-v3.mbta.com/alerts?filter%5Broute_type%5D=0,1',
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final alerts = payload['data'] as List<dynamic>? ?? [];
      final now = DateTime.now();
      return alerts.where((alert) {
        final attributes =
            (alert as Map<String, dynamic>)['attributes']
                as Map<String, dynamic>;
        final periods = attributes['active_period'] as List<dynamic>? ?? [];
        return periods.any((period) {
          final value = period as Map<String, dynamic>;
          final start = DateTime.tryParse(value['start'] as String? ?? '');
          final end = DateTime.tryParse(value['end'] as String? ?? '');
          return (start == null || !now.isBefore(start)) &&
              (end == null || now.isBefore(end));
        });
      }).length;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _checkBackend() async {
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.backendBaseUrl}/health'))
          .timeout(const Duration(seconds: 20));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class _WeatherResult {
  const _WeatherResult({
    required this.temperatureF,
    required this.condition,
    required this.windMph,
    required this.updatedAt,
  });

  final int? temperatureF;
  final String? condition;
  final int? windMph;
  final DateTime? updatedAt;
}
