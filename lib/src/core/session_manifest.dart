/// Metadata about the recorded session environment.
class SessionManifest {
  final String sessionId;
  final DateTime startedAt;
  final String platform; // 'android', 'ios', 'macos', 'windows', 'linux', 'web'
  final double initialWidth;
  final double initialHeight;
  final double initialDevicePixelRatio;
  final String? appVersion;
  final String? buildNumber;
  final String? initialRoute;

  const SessionManifest({
    required this.sessionId,
    required this.startedAt,
    required this.platform,
    required this.initialWidth,
    required this.initialHeight,
    required this.initialDevicePixelRatio,
    this.appVersion,
    this.buildNumber,
    this.initialRoute,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'startedAt': startedAt.toIso8601String(),
        'platform': platform,
        'initialWidth': initialWidth,
        'initialHeight': initialHeight,
        'initialDevicePixelRatio': initialDevicePixelRatio,
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'initialRoute': initialRoute,
      };

  factory SessionManifest.fromJson(Map<String, dynamic> json) {
    return SessionManifest(
      sessionId: json['sessionId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      platform: json['platform'] as String,
      initialWidth: (json['initialWidth'] as num).toDouble(),
      initialHeight: (json['initialHeight'] as num).toDouble(),
      initialDevicePixelRatio:
          (json['initialDevicePixelRatio'] as num).toDouble(),
      appVersion: json['appVersion'] as String?,
      buildNumber: json['buildNumber'] as String?,
      initialRoute: json['initialRoute'] as String?,
    );
  }
}
