import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'event_models.dart';
import 'session_manifest.dart';

/// Complete captured flight session holding metadata and recorded events.
class FlightSession {
  final int formatVersion;
  final SessionManifest manifest;
  final List<FlightEvent> events;

  const FlightSession({
    this.formatVersion = 1,
    required this.manifest,
    required this.events,
  });

  Map<String, dynamic> toJson() => {
        'formatVersion': formatVersion,
        'manifest': manifest.toJson(),
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory FlightSession.fromJson(Map<String, dynamic> json) {
    final version = json['formatVersion'] as int? ?? 1;
    final manifest = SessionManifest.fromJson(
      json['manifest'] as Map<String, dynamic>,
    );
    final rawEvents = json['events'] as List<dynamic>? ?? [];
    final events = rawEvents
        .map((e) => FlightEvent.fromJson(e as Map<String, dynamic>))
        .toList();

    return FlightSession(
      formatVersion: version,
      manifest: manifest,
      events: events,
    );
  }
}

/// Serializes and deserializes [FlightSession] data to and from files or bytes.
class FlightSerializer {
  /// Magic header bytes: 'F', 'L', 'I', 'G', 'H', 'T', 0x01
  static const List<int> magicHeader = [0x46, 0x4C, 0x49, 0x47, 0x48, 0x54, 0x01];

  /// Serializes session to a JSON string.
  static String toJsonString(FlightSession session, {bool pretty = false}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(session.toJson());
    }
    return jsonEncode(session.toJson());
  }

  /// Deserializes session from a JSON string.
  static FlightSession fromJsonString(String jsonString) {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    return FlightSession.fromJson(decoded);
  }

  /// Encodes session to compressed binary bytes (.flightlog format).
  /// Format: [MAGIC_HEADER (7 bytes)] + [GZIP_COMPRESSED_UTF8_JSON]
  static Uint8List toCompressedBytes(FlightSession session) {
    final jsonString = toJsonString(session);
    final utf8Bytes = utf8.encode(jsonString);
    final compressed = gzip.encode(utf8Bytes);

    final builder = BytesBuilder(copy: false);
    builder.add(magicHeader);
    builder.add(compressed);
    return builder.toBytes();
  }

  /// Decodes session from compressed bytes or raw JSON bytes.
  static FlightSession fromBytes(Uint8List bytes) {
    if (bytes.length >= magicHeader.length &&
        _matchesMagic(bytes, magicHeader)) {
      // Compressed binary format
      final compressedData = bytes.sublist(magicHeader.length);
      final decompressed = gzip.decode(compressedData);
      final jsonString = utf8.decode(decompressed);
      return fromJsonString(jsonString);
    } else {
      // Try fallback to uncompressed UTF8 JSON bytes
      final jsonString = utf8.decode(bytes);
      return fromJsonString(jsonString);
    }
  }

  /// Synchronously writes session to file (compressed by default).
  static File writeToFileSync(
    FlightSession session,
    String filePath, {
    bool compress = true,
  }) {
    final file = File(filePath);
    file.parent.createSync(recursive: true);

    if (compress) {
      final bytes = toCompressedBytes(session);
      file.writeAsBytesSync(bytes, flush: true);
    } else {
      final jsonString = toJsonString(session, pretty: true);
      file.writeAsStringSync(jsonString, flush: true);
    }
    return file;
  }

  /// Writes session to file (compressed by default).
  static Future<File> writeToFile(
    FlightSession session,
    String filePath, {
    bool compress = true,
  }) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);

    if (compress) {
      final bytes = toCompressedBytes(session);
      return file.writeAsBytes(bytes, flush: true);
    } else {
      final jsonString = toJsonString(session, pretty: true);
      return file.writeAsString(jsonString, flush: true);
    }
  }

  /// Synchronously reads session from file (automatically handles compressed or plain JSON).
  static FlightSession readFromFileSync(String filePath) {
    final file = File(filePath);
    final bytes = file.readAsBytesSync();
    return fromBytes(bytes);
  }

  /// Reads session from file (automatically handles compressed or plain JSON).
  static Future<FlightSession> readFromFile(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return fromBytes(bytes);
  }

  static bool _matchesMagic(Uint8List bytes, List<int> magic) {
    for (int i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}
