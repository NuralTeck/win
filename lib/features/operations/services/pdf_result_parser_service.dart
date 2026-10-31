import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/database_service.dart';
import '../models/lottery_sambad_result_model.dart';
import '../utils/lottery_result_parser.dart';
import '../utils/winner_verification_engine.dart';

/// Structured outcome of a batch or single PDF scan operation
class PdfBatchScanReport {
  final int totalFiles;
  final int successCount;
  final int failureCount;
  final List<LotterySambadResultModel> parsedResults;
  final int totalWinnersFound;
  final double totalPayoutAmount;
  final List<String> errorMessages;

  const PdfBatchScanReport({
    required this.totalFiles,
    required this.successCount,
    required this.failureCount,
    required this.parsedResults,
    required this.totalWinnersFound,
    required this.totalPayoutAmount,
    required this.errorMessages,
  });

  bool get isAllSuccess => successCount == totalFiles && totalFiles > 0;
  bool get hasAnySuccess => successCount > 0;
}

class PdfResultParserService {
  PdfResultParserService._();
  static final PdfResultParserService instance = PdfResultParserService._();

  /// Comprehensive multi-layer path resolution for Node.js and parse_pdf.js
  /// Works reliably in:
  /// 1. Installed packaged Windows app ({app}\whatsapp_engine)
  /// 2. Flutter Desktop Runner during development (build\windows\x64\runner\Debug)
  /// 3. Normal current working directory execution
  /// 4. System Node.js installation
  (String? nodeExe, String? scriptPath, String? workingDir) resolveEnginePaths() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final currentDir = Directory.current.path;

    final scriptSearchCandidates = [
      // 1. Packaged Release App ({app}\whatsapp_engine\parse_pdf.js)
      p.join(exeDir, 'whatsapp_engine', 'parse_pdf.js'),
      // 2. Dev Runner (build\windows\x64\runner\Debug -> 4 directories up to project root)
      p.normalize(p.join(exeDir, '..', '..', '..', '..', 'whatsapp_engine', 'parse_pdf.js')),
      // 3. Current Working Directory
      p.join(currentDir, 'whatsapp_engine', 'parse_pdf.js'),
      p.join(currentDir, 'parse_pdf.js'),
      // 4. Fallback explicit location
      r'C:\Users\Rajiv Kumar\Desktop\Radhe-Radhe-2\HMS\win\whatsapp_engine\parse_pdf.js',
    ];

    String? foundScript;
    String? workingDir;
    for (final candidate in scriptSearchCandidates) {
      if (File(candidate).existsSync()) {
        foundScript = candidate;
        workingDir = File(candidate).parent.path;
        break;
      }
    }

    final nodeCandidates = [
      if (workingDir != null) p.join(workingDir, 'node.exe'),
      p.join(exeDir, 'whatsapp_engine', 'node.exe'),
      p.normalize(p.join(exeDir, '..', '..', '..', '..', 'whatsapp_engine', 'node.exe')),
      p.join(currentDir, 'whatsapp_engine', 'node.exe'),
      r'C:\Users\Rajiv Kumar\Desktop\Radhe-Radhe-2\HMS\win\whatsapp_engine\node.exe',
      r'C:\Program Files\nodejs\node.exe',
      'node.exe',
      'node',
    ];

    String? foundNode;
    for (final n in nodeCandidates) {
      if (File(n).existsSync() || n == 'node' || n == 'node.exe') {
        foundNode = n;
        break;
      }
    }

    return (foundNode, foundScript, workingDir);
  }

  /// Parses a single file (PDF, TXT, CSV, or Image) into a LotterySambadResultModel
  Future<LotterySambadResultModel?> parseSingleFile({
    required String filePath,
    Uint8List? fileBytes,
    String? defaultShift,
    DateTime? defaultDate,
  }) async {
    final lowerName = p.basename(filePath).toLowerCase();

    // 1. Handle Plain Text or CSV files
    if (lowerName.endsWith('.txt') || lowerName.endsWith('.csv')) {
      try {
        String content = '';
        if (fileBytes != null && fileBytes.isNotEmpty) {
          content = utf8.decode(fileBytes, allowMalformed: true);
        } else if (File(filePath).existsSync()) {
          content = await File(filePath).readAsString();
        }

        if (content.trim().isNotEmpty) {
          final parsed = LotteryResultParser.parseSambadText(
            content,
            drawId: DateTime.now().millisecondsSinceEpoch.toString(),
            drawName: defaultShift ?? 'DEAR 1 PM',
          );
          if (parsed.firstPrize.isNotEmpty || parsed.secondPrizeNumbers.isNotEmpty) {
            return parsed;
          }
        }
      } catch (e) {
        debugPrint('Text/CSV parse error: $e');
      }
    }

    // 2. Handle PDF Files
    if (lowerName.endsWith('.pdf')) {
      // Step A: Fast REST endpoint if local WhatsApp server is running
      try {
        final uri = Uri.parse('http://127.0.0.1:4000/api/parse-pdf');
        final httpReq = await HttpClient()
            .postUrl(uri)
            .timeout(const Duration(milliseconds: 1200));
        httpReq.headers.contentType = ContentType.json;
        httpReq.write(jsonEncode({'filePath': filePath}));
        final httpRes = await httpReq
            .close()
            .timeout(const Duration(milliseconds: 2500));
        if (httpRes.statusCode == 200) {
          final respBody = await httpRes.transform(utf8.decoder).join();
          final decoded = jsonDecode(respBody);
          if (decoded['success'] == true) {
            final model = _buildModelFromDecodedJson(
              decoded,
              fallbackShift: defaultShift,
              fallbackDate: defaultDate,
            );
            if (model != null) return model;
          }
        }
      } catch (_) {}

      // Step B: Node.js parse_pdf.js standalone script
      final (nodeBin, scriptPath, workingDir) = resolveEnginePaths();
      if (nodeBin != null && scriptPath != null) {
        try {
          final runRes = await Process.run(
            nodeBin,
            [scriptPath, filePath],
            workingDirectory: workingDir,
          ).timeout(const Duration(seconds: 15));

          if (runRes.exitCode == 0 && runRes.stdout.toString().trim().isNotEmpty) {
            final decoded = jsonDecode(runRes.stdout.toString().trim());
            if (decoded['success'] == true) {
              final model = _buildModelFromDecodedJson(
                decoded,
                fallbackShift: defaultShift,
                fallbackDate: defaultDate,
              );
              if (model != null) return model;
            }
          } else {
            debugPrint('Node PDF parse stdout: ${runRes.stdout}, stderr: ${runRes.stderr}');
          }
        } catch (e) {
          debugPrint('Node execution exception: $e');
        }
      }

      // Step C: Python script fallback
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final currentDir = Directory.current.path;
      final pyCandidates = [
        p.join(exeDir, 'scripts', 'pdf_sambad_parser.py'),
        p.normalize(p.join(exeDir, '..', '..', '..', '..', 'scripts', 'pdf_sambad_parser.py')),
        p.join(currentDir, 'scripts', 'pdf_sambad_parser.py'),
        r'C:\Users\Rajiv Kumar\Desktop\Radhe-Radhe-2\HMS\win\scripts\pdf_sambad_parser.py',
      ];

      for (final pyPath in pyCandidates) {
        if (File(pyPath).existsSync()) {
          try {
            ProcessResult pyResult;
            try {
              pyResult = await Process.run('python', [pyPath, filePath],
                      workingDirectory: File(pyPath).parent.path)
                  .timeout(const Duration(seconds: 15));
            } catch (_) {
              pyResult = await Process.run('python3', [pyPath, filePath],
                      workingDirectory: File(pyPath).parent.path)
                  .timeout(const Duration(seconds: 15));
            }

            if (pyResult.exitCode == 0 && pyResult.stdout.toString().trim().isNotEmpty) {
              final decoded = jsonDecode(pyResult.stdout.toString().trim());
              final model = _buildModelFromDecodedJson(
                decoded,
                fallbackShift: defaultShift,
                fallbackDate: defaultDate,
              );
              if (model != null) return model;
            }
          } catch (e) {
            debugPrint('Python execution exception: $e');
          }
          break;
        }
      }

      // Step D: Native PDF Byte Stream Text Extractor Fallback
      if (fileBytes != null && fileBytes.isNotEmpty) {
        try {
          final extracted = LotteryResultParser.extractTextFromPdfBytes(fileBytes);
          if (extracted.trim().isNotEmpty) {
            final parsed = LotteryResultParser.parseSambadText(
              extracted,
              drawId: DateTime.now().millisecondsSinceEpoch.toString(),
              drawName: defaultShift ?? 'DEAR 1 PM',
            );
            if (parsed.firstPrize.isNotEmpty || parsed.secondPrizeNumbers.isNotEmpty) {
              return parsed;
            }
          }
        } catch (_) {}
      }
    }

    return null;
  }

  /// Builds a LotterySambadResultModel from decoded JSON returned by parse_pdf.js / Python
  LotterySambadResultModel? _buildModelFromDecodedJson(
    Map<String, dynamic> decoded, {
    String? fallbackShift,
    DateTime? fallbackDate,
  }) {
    String rawDate = decoded['drawDateStr']?.toString().trim() ?? '';
    if (rawDate.isEmpty && fallbackDate != null) {
      rawDate = DateFormat('dd/MM/yyyy').format(fallbackDate);
    } else if (rawDate.isEmpty) {
      rawDate = DateFormat('dd/MM/yyyy').format(DateTime.now());
    }

    // Normalize shift to standard "1 PM", "6 PM", "8 PM"
    String rawShift = decoded['drawShift']?.toString().trim() ?? '';
    if (rawShift.isEmpty && fallbackShift != null) {
      rawShift = fallbackShift;
    }
    String normalizedShift = '1 PM';
    final sLower = rawShift.toLowerCase();
    if (sLower.contains('6') || sLower.contains('day')) {
      normalizedShift = '6 PM';
    } else if (sLower.contains('8') || sLower.contains('night') || sLower.contains('evening')) {
      normalizedShift = '8 PM';
    } else {
      normalizedShift = '1 PM';
    }

    final firstP = decoded['firstPrize']?.toString().trim() ?? '';
    final consoP = decoded['consolationPrize']?.toString().trim() ?? '';

    List<String> toListStr(dynamic val) {
      if (val is List) {
        return val.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      return [];
    }

    final sec = toListStr(decoded['secondPrizeNumbers']);
    final th = toListStr(decoded['thirdPrizeNumbers']);
    final fo = toListStr(decoded['fourthPrizeNumbers']);
    final fi = toListStr(decoded['fifthPrizeNumbers']);

    if (firstP.isEmpty && sec.isEmpty && fi.isEmpty) {
      return null;
    }

    final drawName = 'Dear $normalizedShift';
    final cleanId = '${drawName}_$rawDate'.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    return LotterySambadResultModel(
      drawId: cleanId,
      drawName: drawName,
      drawDateStr: rawDate,
      drawTimeStr: normalizedShift,
      firstPrize: firstP,
      consolationPrize: consoP.isNotEmpty ? consoP : (firstP.length >= 5 ? firstP.substring(firstP.length - 5) : ''),
      secondPrizeNumbers: sec,
      thirdPrizeNumbers: th,
      fourthPrizeNumbers: fo,
      fifthPrizeNumbers: fi,
      publishedAt: DateTime.now(),
      isVerified: true,
    );
  }

  /// Processes multiple PDF/file uploads in a single batch:
  /// - Scans each file with full error isolation
  /// - Automatically saves successful results to SQLite database
  /// - Automatically verifies winners against booking records
  /// - Persists winning claims to winning_claims table
  /// - Calls onProgress callback for realtime UI updates
  Future<PdfBatchScanReport> parseAndSaveMultipleFiles({
    required List<PlatformFile> files,
    String? defaultShift,
    DateTime? defaultDate,
    void Function(int current, int total, String filename)? onProgress,
  }) async {
    final List<LotterySambadResultModel> successfulResults = [];
    final List<String> errors = [];
    int totalWinners = 0;
    double totalPayout = 0.0;

    for (int i = 0; i < files.length; i++) {
      final f = files[i];
      onProgress?.call(i + 1, files.length, f.name);

      String? targetPath = f.path;

      // If file path is not directly available (e.g. web/sandboxed), write bytes to a temp file
      File? tempFile;
      if ((targetPath == null || targetPath.isEmpty) && f.bytes != null) {
        try {
          final tempDir = await getTemporaryDirectory();
          tempFile = File(p.join(tempDir.path, 'scan_${DateTime.now().millisecondsSinceEpoch}_${f.name}'));
          await tempFile.writeAsBytes(f.bytes!);
          targetPath = tempFile.path;
        } catch (_) {}
      }

      if (targetPath == null || targetPath.isEmpty) {
        errors.add('${f.name}: File path could not be resolved');
        continue;
      }

      try {
        final model = await parseSingleFile(
          filePath: targetPath,
          fileBytes: f.bytes,
          defaultShift: defaultShift,
          defaultDate: defaultDate,
        );

        if (model == null || (model.firstPrize.isEmpty && model.secondPrizeNumbers.isEmpty)) {
          errors.add('${f.name}: No winning numbers detected in file');
          continue;
        }

        // Verify winners from database bookings for this draw
        final liveClaims = await WinnerVerificationEngine.verifyDrawFromDatabase(result: model);
        final winCount = liveClaims.length;
        final winPayout = liveClaims.fold<double>(0.0, (acc, c) => acc + c.prizeAmount);

        // Save winning claims in batch
        if (liveClaims.isNotEmpty) {
          await DatabaseService.instance.saveWinningClaimsBatch(liveClaims);
        }

        // Insert or update lottery result in SQLite
        await DatabaseService.instance.insertLotteryResult(
          model,
          verifiedWinnersCount: winCount,
          totalPayoutAmount: winPayout,
        );

        successfulResults.add(model);
        totalWinners += winCount;
        totalPayout += winPayout;
      } catch (err) {
        errors.add('${f.name}: $err');
      } finally {
        if (tempFile != null && tempFile.existsSync()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }
    }

    return PdfBatchScanReport(
      totalFiles: files.length,
      successCount: successfulResults.length,
      failureCount: errors.length,
      parsedResults: successfulResults,
      totalWinnersFound: totalWinners,
      totalPayoutAmount: totalPayout,
      errorMessages: errors,
    );
  }
}
