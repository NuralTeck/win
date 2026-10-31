import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Central Security & Cryptographic Service
/// Handles password hashing with salt, constant-time verification,
/// secret redaction, and archive/file integrity verification.
class SecurityCryptoService {
  SecurityCryptoService._();
  static final SecurityCryptoService instance = SecurityCryptoService._();

  static const List<int> _sqliteMagicHeader = [
    0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
  ]; // "SQLite format 3\0"

  /// Generate a cryptographically secure random salt
  String generateSalt([int length = 16]) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Hash a plaintext password using SHA-256 with a unique salt
  /// Output format: `sha256$<salt>$<hash>`
  String hashPassword(String password, {String? salt}) {
    final effectiveSalt = salt ?? generateSalt(16);
    final combined = utf8.encode('$effectiveSalt:$password');
    final digest = sha256.convert(combined);
    return 'sha256\$$effectiveSalt\$${digest.toString()}';
  }

  /// Verify whether a candidate password matches the stored password.
  /// Supports:
  /// 1. Salted SHA-256 hashes (`sha256$<salt>$<digest>`)
  /// 2. Legacy plaintext passwords for seamless backwards compatibility
  bool verifyPassword(String candidatePassword, String storedPassword) {
    if (storedPassword.isEmpty || candidatePassword.isEmpty) return false;

    if (storedPassword.startsWith('sha256\$')) {
      final parts = storedPassword.split('\$');
      if (parts.length == 3) {
        final salt = parts[1];
        final expectedDigest = parts[2];
        final computedDigest = sha256.convert(utf8.encode('$salt:$candidatePassword')).toString();
        return constantTimeEquals(computedDigest, expectedDigest);
      }
    }

    // Fallback for legacy plaintext entries (with constant-time comparison)
    return constantTimeEquals(candidatePassword, storedPassword);
  }

  /// Check whether a stored password requires an upgrade to a salted hash
  bool requiresRehash(String storedPassword) {
    return !storedPassword.startsWith('sha256\$');
  }

  /// Compares two strings in constant time to prevent timing attacks
  bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Validate SQLite database magic header (First 16 bytes: "SQLite format 3\0")
  bool isValidSqliteHeader(Uint8List bytes) {
    if (bytes.length < 16) return false;
    for (int i = 0; i < 16; i++) {
      if (bytes[i] != _sqliteMagicHeader[i]) return false;
    }
    return true;
  }

  /// Redacts sensitive information from log messages and execution traces
  String redactSensitiveData(String input) {
    if (input.isEmpty) return input;
    var sanitized = input;

    // 1. Redact Bearer tokens
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(Bearer\s+)[a-zA-Z0-9_\-\.]{15,}', caseSensitive: false),
      (m) => '${m.group(1)}[REDACTED_TOKEN]',
    );

    // 2. Redact standard JWTs (three base64url segments separated by dots)
    sanitized = sanitized.replaceAll(
      RegExp(r'eyJ[a-zA-Z0-9_\-]{10,}\.eyJ[a-zA-Z0-9_\-]{10,}\.[a-zA-Z0-9_\-]{10,}'),
      '[REDACTED_JWT]',
    );

    // 3. Redact passwords in JSON / Key-Value patterns
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'("(?:password|cleanPass|secret|masterPin|pin)":\s*")[^"]*(")', caseSensitive: false),
      (m) => '${m.group(1)}[REDACTED_PASSWORD]${m.group(2)}',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'((?:password|secret|masterPin|pin)\s*[:=]\s*)[^\s,;]+', caseSensitive: false),
      (m) => '${m.group(1)}[REDACTED_PASSWORD]',
    );

    // 4. Redact API keys (e.g. AIza..., eyJ...)
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(AIza[0-9A-Za-z-_]{35})'),
      (_) => '[REDACTED_API_KEY]',
    );

    return sanitized;
  }
}

