import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:opscore_pro/core/network/local_api_server.dart';
import 'package:opscore_pro/core/process/models/process_model.dart';
import 'package:opscore_pro/core/process/services/process_manager.dart';
import 'package:opscore_pro/core/services/anti_theft_security_service.dart';
import 'package:opscore_pro/core/services/security_crypto_service.dart';

void main() {
  HttpOverrides.global = null;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('Security: Password Hashing, Salt & Constant-Time Verification', () {
    final crypto = SecurityCryptoService.instance;

    test('Hashes password with SHA-256 and unique salt in sha256\$salt\$digest format', () {
      const pass = 'AdminSecurePass!2026';
      final hash1 = crypto.hashPassword(pass);
      final hash2 = crypto.hashPassword(pass);

      // Hashes must be different because of random unique salts
      expect(hash1, isNot(equals(hash2)));
      expect(hash1, startsWith('sha256\$'));
      expect(hash2, startsWith('sha256\$'));

      // Both hashes verify correctly with the original password
      expect(crypto.verifyPassword(pass, hash1), isTrue);
      expect(crypto.verifyPassword(pass, hash2), isTrue);

      // Wrong password must fail
      expect(crypto.verifyPassword('WrongPassword', hash1), isFalse);
    });

    test('Backwards compatibility: verifies legacy plaintext passwords and flags for rehash', () {
      const legacyPlaintext = 'old_secret_123';

      expect(crypto.verifyPassword(legacyPlaintext, legacyPlaintext), isTrue);
      expect(crypto.verifyPassword('incorrect', legacyPlaintext), isFalse);
      expect(crypto.requiresRehash(legacyPlaintext), isTrue);

      final upgradedHash = crypto.hashPassword(legacyPlaintext);
      expect(crypto.requiresRehash(upgradedHash), isFalse);
    });

    test('Constant-time string comparison protects against timing attacks', () {
      expect(crypto.constantTimeEquals('abc', 'abc'), isTrue);
      expect(crypto.constantTimeEquals('abc', 'abd'), isFalse);
      expect(crypto.constantTimeEquals('abc', 'abcd'), isFalse);
    });
  });

  group('Security: Secret & Credential Redaction in Logs', () {
    final crypto = SecurityCryptoService.instance;

    test('Redacts Bearer tokens, JWTs, and passwords from logs', () {
      const sensitiveText =
          'User logged in. Token: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozG6tQ and {"password": "SuperSecretPassword123", "pin": "9999"}';

      final sanitized = crypto.redactSensitiveData(sensitiveText);

      expect(sanitized, isNot(contains('SuperSecretPassword123')));
      expect(sanitized, isNot(contains('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9')));
      expect(sanitized, contains('[REDACTED_TOKEN]'));
      expect(sanitized, contains('[REDACTED_PASSWORD]'));
    });

    test('ManagedProcess addLog automatically sanitizes sensitive credentials', () {
      final process = ManagedProcess(
        id: 'test_proc',
        title: 'Auth Process',
        action: (ctx) async {},
      );

      process.addLog('Authenticating with Bearer eyJhbGciOiJIUzI1NiIs.eyJzdWIiOiIxMjM.dozG6tQ and password: mySecretPassword123');

      expect(process.logs.length, equals(1));
      final logLine = process.logs.first;
      expect(logLine, isNot(contains('mySecretPassword123')));
      expect(logLine, contains('[REDACTED_PASSWORD]'));
    });
  });

  group('Security: Database Magic Header & Backup Integrity Validation', () {
    final crypto = SecurityCryptoService.instance;

    test('Validates legitimate SQLite 3 file header', () {
      // 16-byte SQLite header: "SQLite format 3\0"
      final validHeader = Uint8List.fromList([
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00,
        0x01, 0x02, 0x03, 0x04
      ]);

      expect(crypto.isValidSqliteHeader(validHeader), isTrue);
    });

    test('Rejects invalid, empty, or malicious files attempting database overwrite', () {
      final invalidFile = Uint8List.fromList(utf8.encode('<html><body>Malicious HTML Payload</body></html>'));
      final emptyFile = Uint8List(0);
      final randomBinary = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);

      expect(crypto.isValidSqliteHeader(invalidFile), isFalse);
      expect(crypto.isValidSqliteHeader(emptyFile), isFalse);
      expect(crypto.isValidSqliteHeader(randomBinary), isFalse);
    });
  });

  group('Security: Anti-Theft Progressive Lockout Defense', () {
    final guard = AntiTheftSecurityService.instance;

    setUp(() async {
      await guard.resetAttempts();
    });

    tearDown(() async {
      await guard.resetAttempts();
    });

    test('Enforces progressive account lockout cooldown after 3 failed attempts', () async {
      expect(guard.isLockedOut, isFalse);

      await guard.registerFailedAttempt(email: 'test@opscore.com', reason: 'Attempt 1');
      expect(guard.isLockedOut, isFalse);

      await guard.registerFailedAttempt(email: 'test@opscore.com', reason: 'Attempt 2');
      expect(guard.isLockedOut, isFalse);

      await guard.registerFailedAttempt(email: 'test@opscore.com', reason: 'Attempt 3');
      expect(guard.isLockedOut, isTrue);
      expect(guard.remainingLockoutDuration.inMinutes, greaterThanOrEqualTo(4));

      // Reset restores access
      await guard.resetAttempts();
      expect(guard.isLockedOut, isFalse);
    });
  });

  group('Security: Embedded Local REST API Server Hardening', () {
    const testPort = 9098;
    const testApiKey = 'test_secret_key_12345';
    final server = LocalApiServer.instance;

    setUp(() async {
      await server.stop();
      await server.start(port: testPort, apiKey: testApiKey);
    });

    tearDown(() async {
      await server.stop();
    });

    test('Rejects unauthenticated requests with 401 Unauthorized', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$testPort/api/v1/health'));
        // No auth header sent
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.unauthorized));
        final body = await utf8.decoder.bind(res).join();
        expect(body, contains('Unauthorized: Valid API key required'));
      } finally {
        client.close();
      }
    });

    test('Accepts requests with valid X-API-Key header', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$testPort/api/v1/health'));
        req.headers.add('X-API-Key', testApiKey);
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.ok));
        final body = await utf8.decoder.bind(res).join();
        expect(body, contains('PhantomManagement POS Counter'));
      } finally {
        client.close();
      }
    });

    test('Accepts requests with valid Authorization Bearer token', () async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$testPort/api/v1/health'));
        req.headers.add('Authorization', 'Bearer $testApiKey');
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.ok));
      } finally {
        client.close();
      }
    });

    test('Rejects oversized payload with 413 or connection abort to protect memory', () async {
      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse('http://127.0.0.1:$testPort/api/v1/booking'));
        req.headers.add('X-API-Key', testApiKey);
        req.headers.contentType = ContentType.json;

        final oversizedBytes = Uint8List(11 * 1024 * 1024); // 11 MB > 10 MB limit
        req.add(oversizedBytes);
        try {
          final res = await req.close();
          expect(res.statusCode, equals(HttpStatus.requestEntityTooLarge));
        } on SocketException catch (e) {
          // On Windows, early server socket close during massive stream causes 10053 abort
          expect(e.message, contains('Write failed'));
        }
      } finally {
        client.close();
      }
    });
  });

  group('Reliability: ProcessManager Guarded Execution & Idempotency', () {
    test('runExclusive prevents duplicate concurrent execution of identical tasks', () async {
      final manager = ProcessManager.instance;
      int executions = 0;

      Future<void> triggerTask() async {
        await manager.runExclusive(
          idempotencyKey: 'critical_payout_lock',
          title: 'Calculate Payout',
          action: (ctx) async {
            executions++;
            await Future.delayed(const Duration(milliseconds: 50));
          },
        );
      }

      final f1 = triggerTask();
      final f2 = triggerTask();
      final f3 = triggerTask();

      await Future.wait([f1, f2, f3]);

      // Double-click lock ensures exactly 1 execution
      expect(executions, equals(1));
    });
  });
}
