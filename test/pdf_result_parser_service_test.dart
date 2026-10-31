import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opscore_pro/core/database/database_service.dart';
import 'package:opscore_pro/features/operations/services/pdf_result_parser_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ticket_sales (
            id TEXT PRIMARY KEY,
            receiptNumber TEXT NOT NULL,
            buyerName TEXT NOT NULL,
            buyerPhone TEXT NOT NULL,
            agentCode TEXT NOT NULL,
            agentName TEXT NOT NULL,
            drawCode TEXT NOT NULL,
            drawName TEXT NOT NULL,
            ticketSeries TEXT NOT NULL,
            ticketNumber TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            pricePerTicket REAL NOT NULL,
            totalAmount REAL NOT NULL,
            commissionAmount REAL NOT NULL,
            status TEXT NOT NULL,
            paymentMode TEXT NOT NULL,
            saleDate TEXT NOT NULL,
            drawDate TEXT NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE lottery_results (
            id TEXT PRIMARY KEY,
            drawName TEXT NOT NULL,
            drawDateStr TEXT NOT NULL,
            drawTimeStr TEXT NOT NULL,
            firstPrize TEXT NOT NULL,
            secondPrizeNumbers TEXT NOT NULL,
            thirdPrizeNumbers TEXT NOT NULL,
            fourthPrizeNumbers TEXT NOT NULL,
            fifthPrizeNumbers TEXT NOT NULL,
            verifiedWinnersCount INTEGER NOT NULL,
            totalPayoutAmount REAL NOT NULL,
            unsoldWinnersCount INTEGER DEFAULT 0,
            unsoldPayoutAmount REAL DEFAULT 0.0,
            publishedAt TEXT NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE winning_claims (
            id TEXT PRIMARY KEY,
            drawId TEXT NOT NULL,
            drawName TEXT NOT NULL,
            drawDate TEXT,
            drawTime TEXT,
            prizeTier TEXT NOT NULL,
            winningNumber TEXT NOT NULL,
            prizeAmount REAL NOT NULL,
            seriesCount INTEGER DEFAULT 1,
            baseAmount REAL DEFAULT 0.0,
            superBonus REAL DEFAULT 0.0,
            specialIncentive REAL DEFAULT 0.0,
            buyerName TEXT NOT NULL,
            sellerName TEXT NOT NULL,
            ticketSeries TEXT NOT NULL,
            ticketNumber TEXT NOT NULL,
            isClaimed INTEGER DEFAULT 0,
            verifiedAt TEXT NOT NULL
          );
        ''');
      },
    );
    DatabaseService.instance.setDatabaseForTesting(db);
  });

  group('PDF Result Parser Service Tests', () {
    test('1. Resolves Node.js and parse_pdf.js paths correctly', () {
      final (nodeExe, scriptPath, workingDir) =
          PdfResultParserService.instance.resolveEnginePaths();
      expect(scriptPath, isNotNull);
      expect(File(scriptPath!).existsSync(), isTrue);
      expect(nodeExe, isNotNull);
      expect(workingDir, isNotNull);
      print('Resolved Node: $nodeExe');
      print('Resolved Script: $scriptPath');
      print('Resolved WorkingDir: $workingDir');
    });

    test('2. Parses single real Lottery Sambad PDF file accurately', () async {
      final realPdf = File(
          r'C:\Users\Rajiv Kumar\Downloads\lottery-sambad-1pm-12-10-2026.pdf');
      if (!realPdf.existsSync()) {
        print('Skipping test 2: real PDF not in Downloads');
        return;
      }

      final model = await PdfResultParserService.instance.parseSingleFile(
        filePath: realPdf.path,
      );

      expect(model, isNotNull);
      expect(model!.firstPrize, equals('79H 68387'));
      expect(model.consolationPrize, equals('68387'));
      expect(model.drawDateStr, equals('12/10/2026'));
      expect(model.drawTimeStr, equals('1 PM'));
      expect(model.secondPrizeNumbers.length, equals(10));
      expect(model.thirdPrizeNumbers.length, equals(10));
      expect(model.fourthPrizeNumbers.length, equals(10));
      expect(model.fifthPrizeNumbers.length, equals(100));
      print('Parsed 1st Prize: ${model.firstPrize}');
      print('Parsed 2nd Count: ${model.secondPrizeNumbers.length}');
      print('Parsed 5th Count: ${model.fifthPrizeNumbers.length}');
    });

    test('3. Parses batch of multiple real PDFs with progress and saves cleanly', () async {
      final f1 = File(r'C:\Users\Rajiv Kumar\Downloads\lottery-sambad-1pm-12-10-2026.pdf');
      final f2 = File(r'C:\Users\Rajiv Kumar\Downloads\lottery-sambad-1pm-13-10-2026.pdf');
      final f3 = File(r'C:\Users\Rajiv Kumar\Downloads\lottery-sambad-1pm-14-10-2026.pdf');

      if (!f1.existsSync() || !f2.existsSync() || !f3.existsSync()) {
        print('Skipping test 3: files not found');
        return;
      }

      final platformFiles = [
        PlatformFile(name: f1.uri.pathSegments.last, size: f1.lengthSync(), path: f1.path),
        PlatformFile(name: f2.uri.pathSegments.last, size: f2.lengthSync(), path: f2.path),
        PlatformFile(name: f3.uri.pathSegments.last, size: f3.lengthSync(), path: f3.path),
      ];

      final progressEvents = <String>[];
      final report = await PdfResultParserService.instance.parseAndSaveMultipleFiles(
        files: platformFiles,
        onProgress: (current, total, filename) {
          progressEvents.add('Processing $current/$total: $filename');
        },
      );

      print('Report errors: ${report.errorMessages}');
      expect(report.totalFiles, equals(3));
      expect(report.successCount, equals(3));
      expect(report.failureCount, equals(0));
      expect(report.parsedResults.length, equals(3));
      expect(progressEvents.length, equals(3));
      print('Report total: ${report.totalFiles}, success: ${report.successCount}');
      for (final r in report.parsedResults) {
        print('Draw: ${r.drawName} (${r.drawDateStr}) -> 1st: ${r.firstPrize}');
      }
    });
  });
}
