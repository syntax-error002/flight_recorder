import 'dart:convert';

typedef RedactFunction = String Function(String input);

/// A rule for sanitizing sensitive data before storage.
class RedactRule {
  final String name;
  final RegExp? pattern;
  final String replacement;
  final RedactFunction? customFunction;

  const RedactRule({
    required this.name,
    this.pattern,
    this.replacement = '[REDACTED]',
    this.customFunction,
  });

  /// Redacts email addresses.
  factory RedactRule.emails() => RedactRule(
        name: 'emails',
        pattern: RegExp(r'[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+'),
        replacement: '[EMAIL_REDACTED]',
      );

  /// Redacts major credit card numbers (13 to 19 digits with optional spaces or dashes).
  factory RedactRule.creditCards() => RedactRule(
        name: 'credit_cards',
        pattern: RegExp(r'\b(?:\d[ -]*?){13,19}\b'),
        replacement: '[CARD_REDACTED]',
      );

  /// Redacts Bearer authentication tokens.
  factory RedactRule.bearerTokens() => RedactRule(
        name: 'bearer_tokens',
        pattern: RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*'),
        replacement: 'Bearer [REDACTED_TOKEN]',
      );

  String apply(String input) {
    if (customFunction != null) {
      return customFunction!(input);
    }
    if (pattern != null) {
      return input.replaceAll(pattern!, replacement);
    }
    return input;
  }
}

/// The engine that redacts sensitive information from headers, URLs, and JSON payloads.
class RedactionEngine {
  final List<RedactRule> rules;
  final Set<String> sensitiveHeaders;
  final Set<String> sensitiveKeys;

  RedactionEngine({
    List<RedactRule>? rules,
    Set<String>? sensitiveHeaders,
    Set<String>? sensitiveKeys,
  })  : rules = rules ??
            [
              RedactRule.emails(),
              RedactRule.creditCards(),
              RedactRule.bearerTokens(),
            ],
        sensitiveHeaders = sensitiveHeaders ??
            {
              'authorization',
              'cookie',
              'set-cookie',
              'x-api-key',
              'api-key',
              'proxy-authorization',
            },
        sensitiveKeys = sensitiveKeys ??
            {
              'password',
              'secret',
              'token',
              'access_token',
              'refresh_token',
              'api_key',
              'apikey',
              'cvv',
              'ssn',
              'pin',
            };

  /// Sanitizes HTTP headers.
  Map<String, String> sanitizeHeaders(Map<String, String> headers) {
    final sanitized = <String, String>{};
    for (final entry in headers.entries) {
      final lowerKey = entry.key.toLowerCase();
      if (sensitiveHeaders.contains(lowerKey)) {
        sanitized[entry.key] = '[REDACTED]';
      } else {
        sanitized[entry.key] = sanitizeString(entry.value);
      }
    }
    return sanitized;
  }

  /// Sanitizes a string through all configured rules.
  String sanitizeString(String input) {
    var output = input;
    for (final rule in rules) {
      output = rule.apply(output);
    }
    return output;
  }

  /// Alias for sanitizeString.
  String redact(String input) => sanitizeString(input);

  /// Convenience method for nullable string redaction.
  String? maybeRedact(String? input) => input == null ? null : sanitizeString(input);

  /// Sanitizes a JSON payload (String or Object).
  String? sanitizeJsonPayload(String? rawPayload) {
    if (rawPayload == null || rawPayload.isEmpty) return rawPayload;

    try {
      final decoded = jsonDecode(rawPayload);
      final sanitizedObj = _sanitizeObject(decoded);
      return jsonEncode(sanitizedObj);
    } catch (_) {
      // If it's not valid JSON, treat as raw string
      return sanitizeString(rawPayload);
    }
  }

  dynamic _sanitizeObject(dynamic obj) {
    if (obj is Map) {
      final result = <String, dynamic>{};
      for (final entry in obj.entries) {
        final keyStr = entry.key.toString();
        final lowerKey = keyStr.toLowerCase();

        if (sensitiveKeys.any((s) => lowerKey.contains(s))) {
          result[keyStr] = '[REDACTED]';
        } else {
          result[keyStr] = _sanitizeObject(entry.value);
        }
      }
      return result;
    } else if (obj is List) {
      return obj.map(_sanitizeObject).toList();
    } else if (obj is String) {
      return sanitizeString(obj);
    }
    return obj;
  }
}
