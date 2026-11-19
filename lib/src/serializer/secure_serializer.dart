// lib/src/serializer/secure_serializer.dart
//
// Extends the flight_recorder serialization stack with an encrypted
// `.eflightlog` format.
//
// File format:
//   [ MAGIC  8 bytes: 'EFLIGHT\x01' ]
//   [ encrypted payload: output of CryptoEngine.encrypt(gzip(json)) ]
//
// The encrypted payload is the raw bytes returned by [CryptoEngine.encrypt],
// which itself carries a 12-byte nonce and 32-byte HMAC tag.
//
// Plain `.flightlog` auto-detection:
//   [readAutoDetect] peeks at the first 8 bytes; if they match the EFLIGHT
//   magic it uses [SecureFlightSerializer], otherwise it falls back to the
//   plain [FlightSerializer].

// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/crypto_engine.dart';
import '../core/serializer.dart';

// ---------------------------------------------------------------------------
// Magic bytes
// ---------------------------------------------------------------------------

/// 8-byte magic header that identifies a `.eflightlog` file.
///
/// Value: ASCII `EFLIGHT` followed by version byte `0x01`.
const List<int> _EFLIGHT_MAGIC = [
  0x45, 0x46, 0x4C, 0x49, 0x47, 0x48, 0x54, 0x01, // 'EFLIGHT\x01'
];

// ---------------------------------------------------------------------------
// SecureFlightSerializer
// ---------------------------------------------------------------------------

/// Serialises / deserialises [FlightSession] objects to / from encrypted
/// `.eflightlog` files.
///
/// Encryption uses [CryptoEngine] (ChaCha20-inspired stream cipher +
/// HMAC-SHA256), applied on top of GZIP-compressed JSON.
///
/// Example usage:
/// ```dart
/// final key    = CryptoEngine.generateRandomKey();
/// final crypto = CryptoEngine.withKey(key);
/// final ser    = SecureFlightSerializer(crypto: crypto);
///
/// // Write
/// final file = await ser.writeEncryptedToFile(session, '/tmp/my.eflightlog');
///
/// // Read back
/// final loaded = await ser.readEncryptedFromFile('/tmp/my.eflightlog');
/// ```
class SecureFlightSerializer {
  final CryptoEngine crypto;

  const SecureFlightSerializer({required this.crypto});

  // -------------------------------------------------------------------------
  // In-memory encode / decode
  // -------------------------------------------------------------------------

  /// Serialises [session] to an encrypted `.eflightlog` byte array.
  ///
  /// Layout:
  /// ```
  /// [ 8-byte MAGIC | encrypted(gzip(UTF-8 JSON)) ]
  /// ```
  Uint8List toEncryptedBytes(FlightSession session) {
    // 1. JSON encode
    final String jsonStr = jsonEncode(session.toJson());
    final Uint8List jsonBytes = Uint8List.fromList(utf8.encode(jsonStr));

    // 2. GZIP compress
    final Uint8List compressed =
        Uint8List.fromList(GZipCodec().encode(jsonBytes));

    // 3. Encrypt
    final Uint8List cipherPayload = crypto.encrypt(compressed);

    // 4. Prepend magic header
    final Uint8List result =
        Uint8List(_EFLIGHT_MAGIC.length + cipherPayload.length);
    result.setRange(0, _EFLIGHT_MAGIC.length, _EFLIGHT_MAGIC);
    result.setRange(_EFLIGHT_MAGIC.length, result.length, cipherPayload);
    return result;
  }

  /// Decrypts and deserialises a [FlightSession] from [bytes] produced by
  /// [toEncryptedBytes].
  ///
  /// Throws [EFlightFormatException] if the magic bytes are missing or wrong.
  /// Throws [CryptoAuthException] (from [CryptoEngine]) if authentication fails.
  FlightSession fromEncryptedBytes(Uint8List bytes) {
    // 1. Validate magic
    _assertMagic(bytes);

    // 2. Strip magic
    final Uint8List cipherPayload =
        Uint8List.sublistView(bytes, _EFLIGHT_MAGIC.length);

    // 3. Decrypt
    final Uint8List compressed = crypto.decrypt(cipherPayload);

    // 4. GZIP decompress
    final Uint8List jsonBytes =
        Uint8List.fromList(GZipCodec().decode(compressed));

    // 5. JSON decode
    final String jsonStr = utf8.decode(jsonBytes);
    final Map<String, dynamic> json =
        jsonDecode(jsonStr) as Map<String, dynamic>;

    return FlightSession.fromJson(json);
  }

  // -------------------------------------------------------------------------
  // File I/O
  // -------------------------------------------------------------------------

  /// Synchronously serialises [session], encrypts it, and writes the result to [filePath].
  File writeEncryptedToFileSync(FlightSession session, String filePath) {
    final String path = _enforceExtension(filePath, '.eflightlog');
    final Uint8List bytes = toEncryptedBytes(session);
    final File file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }

  /// Serialises [session], encrypts it, and writes the result to [filePath].
  ///
  /// The file extension is normalised to `.eflightlog` automatically; a
  /// trailing `.flightlog` or missing extension is replaced / appended.
  ///
  /// Returns the [File] that was written.
  Future<File> writeEncryptedToFile(
      FlightSession session, String filePath) async {
    final String path = _enforceExtension(filePath, '.eflightlog');
    final Uint8List bytes = toEncryptedBytes(session);
    final File file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Synchronously reads the file at [filePath], decrypts, and deserialises the [FlightSession].
  FlightSession readEncryptedFromFileSync(String filePath) {
    final Uint8List bytes = File(filePath).readAsBytesSync();
    return fromEncryptedBytes(bytes);
  }

  /// Reads the file at [filePath], decrypts, and deserialises the
  /// [FlightSession].
  ///
  /// Throws [EFlightFormatException] if the file is not a valid
  /// `.eflightlog` file.
  Future<FlightSession> readEncryptedFromFile(String filePath) async {
    final Uint8List bytes = await File(filePath).readAsBytes();
    return fromEncryptedBytes(bytes);
  }

  // -------------------------------------------------------------------------
  // Auto-detect static helper
  // -------------------------------------------------------------------------

  /// Reads [filePath] and auto-detects whether it is an encrypted
  /// `.eflightlog` or a plain `.flightlog`.
  ///
  /// - If the file starts with the EFLIGHT magic, [crypto] **must** be
  ///   provided; a [StateError] is thrown otherwise.
  /// - If the file is a plain `.flightlog`, [plainSerializer] is used.
  ///   If [plainSerializer] is `null` a [StateError] is thrown.
  ///
  /// Example:
  /// ```dart
  /// final session = await SecureFlightSerializer.readAutoDetect(
  ///   '/recordings/session.eflightlog',
  ///   crypto: CryptoEngine.withKey(savedKey),
  /// );
  /// ```
  static Future<FlightSession> readAutoDetect(
    String filePath, {
    CryptoEngine? crypto,
  }) async {
    final Uint8List bytes = await File(filePath).readAsBytes();

    if (_hasEflightMagic(bytes)) {
      if (crypto == null) {
        throw StateError(
            'readAutoDetect: file "$filePath" is encrypted (.eflightlog) '
            'but no CryptoEngine was provided.');
      }
      final SecureFlightSerializer ser = SecureFlightSerializer(crypto: crypto);
      return ser.fromEncryptedBytes(bytes);
    }

    return FlightSerializer.readFromFile(filePath);
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Returns `true` if [bytes] begin with the 8-byte `.eflightlog` magic header.
  static bool hasEflightMagic(Uint8List bytes) => _hasEflightMagic(bytes);

  static bool _hasEflightMagic(Uint8List bytes) {
    if (bytes.length < _EFLIGHT_MAGIC.length) return false;
    for (int i = 0; i < _EFLIGHT_MAGIC.length; i++) {
      if (bytes[i] != _EFLIGHT_MAGIC[i]) return false;
    }
    return true;
  }

  static void _assertMagic(Uint8List bytes) {
    if (!_hasEflightMagic(bytes)) {
      final String found = bytes.length >= _EFLIGHT_MAGIC.length
          ? bytes
              .sublist(0, _EFLIGHT_MAGIC.length)
              .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
              .join(' ')
          : '<too short>';
      throw EFlightFormatException('Invalid .eflightlog magic. Expected '
          '${_EFLIGHT_MAGIC.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}, '
          'got $found.');
    }
  }

  static String _enforceExtension(String path, String ext) {
    // Strip recognised flight-recorder extensions then add the target one.
    for (final String old in ['.eflightlog', '.flightlog']) {
      if (path.endsWith(old)) {
        return '${path.substring(0, path.length - old.length)}$ext';
      }
    }
    return '$path$ext';
  }
}

// ---------------------------------------------------------------------------
// Exception types
// ---------------------------------------------------------------------------

/// Thrown when a file does not begin with the expected EFLIGHT magic bytes.
class EFlightFormatException implements Exception {
  final String message;
  const EFlightFormatException(this.message);

  @override
  String toString() => 'EFlightFormatException: $message';
}
