// lib/src/core/crypto_engine.dart
//
// Production-quality pure-Dart stream cipher + HMAC-SHA256 authentication.
//
// Wire format for an encrypted payload:
//   [ 12-byte nonce | 32-byte HMAC-SHA256 tag | ciphertext ]
//
// Stream cipher: ChaCha20-inspired quarter-round construction.
//   - 256-bit key, 96-bit nonce, 32-bit counter.
//   - Keystream blocks are 64 bytes (512 bits), identical block size to ChaCha20.
//
// HMAC-SHA256: Fully hand-rolled SHA-256 + HMAC per RFC 2104.
//   - Computed over (nonce || ciphertext); tag stored before ciphertext.
//
// Key derivation: PBKDF2 with HMAC-SHA256 PRF, 10 000 iterations (RFC 2898).

// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Low-level SHA-256
// ---------------------------------------------------------------------------

/// Pure-Dart SHA-256 implementation (FIPS 180-4).
class _Sha256 {
  // Initial hash values H0..H7
  static const List<int> _H = [
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];

  // Round constants K0..K63
  static const List<int> _K = [
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  /// Computes SHA-256 digest over [data]. Returns 32 bytes.
  static Uint8List hash(Uint8List data) {
    // 1. Pre-processing: padding
    final int msgLen = data.length;
    // Bit-length as big-endian 64-bit
    final int bitLen = msgLen * 8;

    // Append 0x80, then zeros so that (length + 1 + zeros) ≡ 56 (mod 64)
    int padded = msgLen + 1;
    while (padded % 64 != 56) {
      padded++;
    }
    final Uint8List msg = Uint8List(padded + 8);
    msg.setRange(0, msgLen, data);
    msg[msgLen] = 0x80;
    // Big-endian 64-bit bit length at the end
    final ByteData bd = ByteData.sublistView(msg);
    // Upper 32 bits of bitLen (for messages < 2^32 bits, this is 0)
    bd.setUint32(padded, 0, Endian.big);
    bd.setUint32(padded + 4, bitLen & 0xffffffff, Endian.big);

    // 2. Process each 512-bit (64-byte) block
    var h0 = _H[0], h1 = _H[1], h2 = _H[2], h3 = _H[3];
    var h4 = _H[4], h5 = _H[5], h6 = _H[6], h7 = _H[7];

    final Uint32List w = Uint32List(64);

    for (int i = 0; i < msg.length; i += 64) {
      final ByteData block = ByteData.sublistView(msg, i, i + 64);

      // Prepare message schedule
      for (int t = 0; t < 16; t++) {
        w[t] = block.getUint32(t * 4, Endian.big);
      }
      for (int t = 16; t < 64; t++) {
        final int s0 =
            _rotr32(w[t - 15], 7) ^ _rotr32(w[t - 15], 18) ^ (w[t - 15] >>> 3);
        final int s1 =
            _rotr32(w[t - 2], 17) ^ _rotr32(w[t - 2], 19) ^ (w[t - 2] >>> 10);
        w[t] = (_add32(w[t - 16], s0) + w[t - 7] + s1) & 0xffffffff;
      }

      var a = h0, b = h1, c = h2, d = h3;
      var e = h4, f = h5, g = h6, h = h7;

      for (int t = 0; t < 64; t++) {
        final int s1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
        final int ch = (e & f) ^ (~e & g);
        final int temp1 =
            _add32(_add32(_add32(_add32(h, s1), ch), _K[t]), w[t]);
        final int s0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
        final int maj = (a & b) ^ (a & c) ^ (b & c);
        final int temp2 = _add32(s0, maj);

        h = g;
        g = f;
        f = e;
        e = _add32(d, temp1);
        d = c;
        c = b;
        b = a;
        a = _add32(temp1, temp2);
      }

      h0 = _add32(h0, a);
      h1 = _add32(h1, b);
      h2 = _add32(h2, c);
      h3 = _add32(h3, d);
      h4 = _add32(h4, e);
      h5 = _add32(h5, f);
      h6 = _add32(h6, g);
      h7 = _add32(h7, h);
    }

    // 3. Produce final digest
    final Uint8List digest = Uint8List(32);
    final ByteData out = ByteData.sublistView(digest);
    out.setUint32(0, h0, Endian.big);
    out.setUint32(4, h1, Endian.big);
    out.setUint32(8, h2, Endian.big);
    out.setUint32(12, h3, Endian.big);
    out.setUint32(16, h4, Endian.big);
    out.setUint32(20, h5, Endian.big);
    out.setUint32(24, h6, Endian.big);
    out.setUint32(28, h7, Endian.big);
    return digest;
  }

  static int _rotr32(int x, int n) =>
      ((x >>> n) | (x << (32 - n))) & 0xffffffff;

  static int _add32(int a, int b) => (a + b) & 0xffffffff;
}

// ---------------------------------------------------------------------------
// HMAC-SHA256  (RFC 2104)
// ---------------------------------------------------------------------------

class _HmacSha256 {
  static const int _blockSize = 64; // SHA-256 block size in bytes

  /// Returns 32-byte HMAC-SHA256 for [message] authenticated with [key].
  static Uint8List compute(Uint8List key, Uint8List message) {
    // If key is longer than block size, hash it first
    Uint8List k =
        key.length > _blockSize ? _Sha256.hash(key) : Uint8List.fromList(key);

    // Pad key to block size
    final Uint8List kPadded = Uint8List(_blockSize);
    kPadded.setRange(0, k.length, k);

    // ipad = 0x36, opad = 0x5c
    final Uint8List iPad = Uint8List(_blockSize);
    final Uint8List oPad = Uint8List(_blockSize);
    for (int i = 0; i < _blockSize; i++) {
      iPad[i] = kPadded[i] ^ 0x36;
      oPad[i] = kPadded[i] ^ 0x5c;
    }

    // inner = SHA256(iPad || message)
    final Uint8List inner = Uint8List(iPad.length + message.length);
    inner.setRange(0, iPad.length, iPad);
    inner.setRange(iPad.length, inner.length, message);
    final Uint8List innerHash = _Sha256.hash(inner);

    // outer = SHA256(oPad || inner)
    final Uint8List outer = Uint8List(oPad.length + innerHash.length);
    outer.setRange(0, oPad.length, oPad);
    outer.setRange(oPad.length, outer.length, innerHash);
    return _Sha256.hash(outer);
  }
}

// ---------------------------------------------------------------------------
// ChaCha20-inspired stream cipher
// ---------------------------------------------------------------------------
//
// State layout (16 × uint32):
//   Words  0- 3: constants  "expa", "nd 3", "2-by", "te k"
//   Words  4-11: key (256 bits = 8 × uint32, little-endian)
//   Word  12   : block counter (starts at 0, increments per 64-byte block)
//   Words 13-15: nonce (96 bits = 3 × uint32, little-endian)

class _ChaCha20Like {
  static const List<int> _SIGMA = [
    0x61707865, // "expa"
    0x3320646e, // "nd 3"
    0x79622d32, // "2-by"
    0x6b206574, // "te k"
  ];

  static const int _ROUNDS = 20; // 20 rounds (10 double-rounds) like ChaCha20

  /// Produces 64 bytes of keystream for [key] (32 bytes), [nonce] (12 bytes),
  /// and block [counter].
  static Uint8List _block(Uint8List key, Uint8List nonce, int counter) {
    assert(key.length == 32);
    assert(nonce.length == 12);

    final Uint32List state = Uint32List(16);
    // Constants
    state[0] = _SIGMA[0];
    state[1] = _SIGMA[1];
    state[2] = _SIGMA[2];
    state[3] = _SIGMA[3];
    // Key (little-endian 32-bit words)
    final ByteData keyBd = ByteData.sublistView(key);
    for (int i = 0; i < 8; i++) {
      state[4 + i] = keyBd.getUint32(i * 4, Endian.little);
    }
    // Counter
    state[12] = counter & 0xffffffff;
    // Nonce (little-endian)
    final ByteData nonceBd = ByteData.sublistView(nonce);
    state[13] = nonceBd.getUint32(0, Endian.little);
    state[14] = nonceBd.getUint32(4, Endian.little);
    state[15] = nonceBd.getUint32(8, Endian.little);

    final Uint32List working = Uint32List.fromList(state);

    // Core: _ROUNDS / 2 double-rounds
    for (int r = 0; r < _ROUNDS ~/ 2; r++) {
      // Column rounds
      _quarterRound(working, 0, 4, 8, 12);
      _quarterRound(working, 1, 5, 9, 13);
      _quarterRound(working, 2, 6, 10, 14);
      _quarterRound(working, 3, 7, 11, 15);
      // Diagonal rounds
      _quarterRound(working, 0, 5, 10, 15);
      _quarterRound(working, 1, 6, 11, 12);
      _quarterRound(working, 2, 7, 8, 13);
      _quarterRound(working, 3, 4, 9, 14);
    }

    // Add original state
    final Uint8List output = Uint8List(64);
    final ByteData outBd = ByteData.sublistView(output);
    for (int i = 0; i < 16; i++) {
      outBd.setUint32(
          i * 4, (working[i] + state[i]) & 0xffffffff, Endian.little);
    }
    return output;
  }

  static void _quarterRound(Uint32List s, int a, int b, int c, int d) {
    s[a] = _add32(s[a], s[b]);
    s[d] = _rotl32(s[d] ^ s[a], 16);
    s[c] = _add32(s[c], s[d]);
    s[b] = _rotl32(s[b] ^ s[c], 12);
    s[a] = _add32(s[a], s[b]);
    s[d] = _rotl32(s[d] ^ s[a], 8);
    s[c] = _add32(s[c], s[d]);
    s[b] = _rotl32(s[b] ^ s[c], 7);
  }

  static int _rotl32(int x, int n) =>
      ((x << n) | (x >>> (32 - n))) & 0xffffffff;

  static int _add32(int a, int b) => (a + b) & 0xffffffff;

  /// XORs [plaintext] with the keystream generated from [key] + [nonce].
  /// Returns the resulting ciphertext (or plaintext, since XOR is symmetric).
  static Uint8List xorStream(Uint8List key, Uint8List nonce, Uint8List data) {
    final Uint8List result = Uint8List(data.length);
    int pos = 0;
    int counter = 0;
    while (pos < data.length) {
      final Uint8List block = _block(key, nonce, counter);
      final int take = (data.length - pos < 64) ? data.length - pos : 64;
      for (int i = 0; i < take; i++) {
        result[pos + i] = data[pos + i] ^ block[i];
      }
      pos += take;
      counter++;
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// PBKDF2-HMAC-SHA256
// ---------------------------------------------------------------------------

class _Pbkdf2 {
  /// Derives [dkLen] bytes from [password] and [salt] using PBKDF2-HMAC-SHA256
  /// with [iterations] iterations (RFC 2898 §5.2).
  static Uint8List derive({
    required Uint8List password,
    required Uint8List salt,
    required int iterations,
    required int dkLen,
  }) {
    final int hLen = 32; // SHA-256 output length
    final int l = (dkLen / hLen).ceil();
    final Uint8List dk = Uint8List(l * hLen);

    for (int i = 1; i <= l; i++) {
      // U1 = PRF(password, salt || INT(i))
      final Uint8List saltI = Uint8List(salt.length + 4);
      saltI.setRange(0, salt.length, salt);
      ByteData.sublistView(saltI).setUint32(salt.length, i, Endian.big);

      Uint8List u = _HmacSha256.compute(password, saltI);
      final Uint8List t = Uint8List.fromList(u);

      for (int j = 1; j < iterations; j++) {
        u = _HmacSha256.compute(password, u);
        for (int k = 0; k < hLen; k++) {
          t[k] ^= u[k];
        }
      }

      dk.setRange((i - 1) * hLen, i * hLen, t);
    }
    return Uint8List.sublistView(dk, 0, dkLen);
  }
}

// ---------------------------------------------------------------------------
// CryptoEngine  (public API)
// ---------------------------------------------------------------------------

/// Encryption / decryption engine for `.flightlog` and `.eflightlog` files.
///
/// Uses a ChaCha20-identical stream cipher for confidentiality and
/// HMAC-SHA256 for authenticated integrity.
///
/// Wire format produced by [encrypt]:
/// ```
/// [ 12-byte nonce | 32-byte HMAC-SHA256 | ciphertext ]
/// ```
/// The HMAC covers `nonce || ciphertext`.
class CryptoEngine {
  static const int _keyLength = 32;
  static const int _nonceLength = 12;
  static const int _tagLength = 32; // HMAC-SHA256
  static const int _overhead = _nonceLength + _tagLength; // 44 bytes

  /// 256-bit symmetric key.
  final Uint8List key;
  final Uint8List? salt;

  CryptoEngine._(this.key, {this.salt}) {
    if (key.length != _keyLength) {
      throw ArgumentError(
          'CryptoEngine: key must be exactly $_keyLength bytes, '
          'got ${key.length}.');
    }
  }

  // -------------------------------------------------------------------------
  // Factories
  // -------------------------------------------------------------------------

  /// Constructs a [CryptoEngine] with an explicit [key].
  factory CryptoEngine.withKey(Uint8List key) => CryptoEngine._(key);

  /// Constructs a [CryptoEngine] derived from [passphrase] using PBKDF2.
  factory CryptoEngine.withPassphrase(String passphrase,
      {Uint8List? salt, int iterations = 10000}) {
    final effectiveSalt =
        salt ?? Uint8List.fromList(utf8.encode('flight_recorder_salt_v1'));
    return CryptoEngine._(
        deriveKey(passphrase, effectiveSalt, iterations: iterations),
        salt: salt != null ? effectiveSalt : null);
  }

  static Uint8List generateSalt([int length = 16]) => _secureRandom(length);

  factory CryptoEngine.withPassphraseAndRandomSalt(String passphrase,
      {int iterations = 10000}) {
    final salt = generateSalt(16);
    return CryptoEngine._(deriveKey(passphrase, salt, iterations: iterations),
        salt: salt);
  }

  /// Constructs a [CryptoEngine] with a freshly generated random key.
  factory CryptoEngine.generateKey() => CryptoEngine._(generateRandomKey());

  // -------------------------------------------------------------------------
  // Core encrypt / decrypt
  // -------------------------------------------------------------------------

  /// Encrypts [plaintext] and returns `[nonce | hmac | ciphertext]`.
  Uint8List encrypt(Uint8List plaintext) {
    // 1. Fresh random nonce
    final Uint8List nonce = _secureRandom(_nonceLength);

    // 2. Encrypt
    final Uint8List ciphertext = _ChaCha20Like.xorStream(key, nonce, plaintext);

    // 3. Compute HMAC over (nonce || ciphertext)
    final Uint8List hmacInput = Uint8List(nonce.length + ciphertext.length);
    hmacInput.setRange(0, nonce.length, nonce);
    hmacInput.setRange(nonce.length, hmacInput.length, ciphertext);
    final Uint8List tag = _HmacSha256.compute(key, hmacInput);

    // 4. Assemble output
    final Uint8List output = Uint8List(_overhead + ciphertext.length);
    output.setRange(0, _nonceLength, nonce);
    output.setRange(_nonceLength, _nonceLength + _tagLength, tag);
    output.setRange(_overhead, output.length, ciphertext);
    return output;
  }

  /// Decrypts bytes produced by [encrypt]. Throws [CryptoAuthException] if the
  /// HMAC tag does not match.
  Uint8List decrypt(Uint8List encryptedBytes) {
    if (encryptedBytes.length < _overhead) {
      throw CryptoAuthException(
          'Encrypted payload too short: ${encryptedBytes.length} bytes, '
          'minimum is $_overhead.');
    }

    final Uint8List nonce =
        Uint8List.sublistView(encryptedBytes, 0, _nonceLength);
    final Uint8List storedTag = Uint8List.sublistView(
        encryptedBytes, _nonceLength, _nonceLength + _tagLength);
    final Uint8List ciphertext =
        Uint8List.sublistView(encryptedBytes, _overhead);

    // Recompute HMAC
    final Uint8List hmacInput = Uint8List(nonce.length + ciphertext.length);
    hmacInput.setRange(0, nonce.length, nonce);
    hmacInput.setRange(nonce.length, hmacInput.length, ciphertext);
    final Uint8List expectedTag = _HmacSha256.compute(key, hmacInput);

    // Constant-time comparison
    if (!_constantTimeEqual(storedTag, expectedTag)) {
      throw CryptoAuthException(
          'HMAC-SHA256 verification failed: message is corrupt or key is wrong.');
    }

    return _ChaCha20Like.xorStream(key, nonce, ciphertext);
  }

  // -------------------------------------------------------------------------
  // Static helpers
  // -------------------------------------------------------------------------

  /// Derives a 32-byte key from [passphrase] and [salt] using
  /// PBKDF2-HMAC-SHA256 with 10 000 iterations.
  static Uint8List deriveKey(String passphrase, Uint8List salt,
      {int iterations = 10000}) {
    final Uint8List passwordBytes = Uint8List.fromList(utf8.encode(passphrase));
    return _Pbkdf2.derive(
      password: passwordBytes,
      salt: salt,
      iterations: iterations,
      dkLen: _keyLength,
    );
  }

  /// Generates a cryptographically secure random 32-byte key.
  static Uint8List generateRandomKey() => _secureRandom(_keyLength);

  /// Encodes [key] as a Base64 string suitable for safe storage.
  static String encodeKey(Uint8List key) => base64Url.encode(key);

  /// Decodes a Base64 string produced by [encodeKey] back into raw key bytes.
  static Uint8List decodeKey(String base64Key) =>
      Uint8List.fromList(base64Url.decode(base64Key));

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Generates [length] cryptographically secure random bytes.
  static Uint8List _secureRandom(int length) {
    final Random rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => rng.nextInt(256)));
  }

  /// Constant-time comparison of two byte arrays to prevent timing attacks.
  static bool _constantTimeEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

// ---------------------------------------------------------------------------
// Exception types
// ---------------------------------------------------------------------------

/// Thrown when HMAC-SHA256 authentication fails during decryption.
class CryptoAuthException implements Exception {
  final String message;
  const CryptoAuthException(this.message);

  @override
  String toString() => 'CryptoAuthException: $message';
}
