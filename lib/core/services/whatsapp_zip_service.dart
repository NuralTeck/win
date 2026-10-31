import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// Represents an image/media slip extracted from a WhatsApp ZIP export
class WhatsAppZipMediaItem {
  final String filename;
  final Uint8List bytes;
  final String? sender;
  final DateTime? date;
  final String? shift;

  WhatsAppZipMediaItem({
    required this.filename,
    required this.bytes,
    this.sender,
    this.date,
    this.shift,
  });
}

/// Result of unpacking a WhatsApp export ZIP
class WhatsAppZipResult {
  final String? chatText;
  final List<WhatsAppZipMediaItem> mediaImages;
  final int totalFiles;
  final String? chatFileName;

  WhatsAppZipResult({
    this.chatText,
    required this.mediaImages,
    required this.totalFiles,
    this.chatFileName,
  });

  bool get hasChatText => chatText != null && chatText!.trim().isNotEmpty;
  bool get hasMediaImages => mediaImages.isNotEmpty;
}

class WhatsAppZipService {
  WhatsAppZipService._();
  static final WhatsAppZipService instance = WhatsAppZipService._();

  static const _supportedImageExts = {'jpg', 'jpeg', 'png', 'webp', 'bmp'};

  /// Extracts chat text and media slips from a WhatsApp export ZIP archive
  Future<WhatsAppZipResult> extractZip(Uint8List zipBytes) async {
    return compute(_unpackZipIsolate, zipBytes);
  }

  static const int maxZipFiles = 500;
  static const int maxDecompressedBytes = 250 * 1024 * 1024; // 250 MB safety budget

  static WhatsAppZipResult _unpackZipIsolate(Uint8List zipBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      if (archive.files.length > maxZipFiles) {
        throw FormatException('ZIP archive exceeds safety bounds: contains ${archive.files.length} files (maximum permitted: $maxZipFiles)');
      }

      String? chatText;
      String? chatFileName;
      final List<ArchiveFile> rawImageFiles = [];
      int totalDecompressedBytes = 0;

      for (final file in archive.files) {
        if (!file.isFile) continue;
        totalDecompressedBytes += file.size;
        if (totalDecompressedBytes > maxDecompressedBytes) {
          throw FormatException('ZIP archive exceeds safety memory budget: decompressed size exceeds 250 MB');
        }

        final name = file.name;
        final lower = name.toLowerCase();

        // 1. WhatsApp Chat Text File Detection
        if (lower.endsWith('.txt')) {
          final content = utf8.decode(file.content as List<int>, allowMalformed: true);
          // Prefer _chat.txt or the largest text file
          if (chatText == null || lower.contains('_chat') || content.length > chatText.length) {
            chatText = content;
            chatFileName = name;
          }
        } else {
          // 2. Image Media Slips Detection
          final ext = lower.split('.').last;
          if (_supportedImageExts.contains(ext)) {
            rawImageFiles.add(file);
          }
        }
      }

      // Helper to extract date from filename like IMG-20260901-WA0004.jpg or 2026-09-01
      DateTime? extractDateFromFilename(String filename) {
        final m1 = RegExp(r'(\d{4})(\d{2})(\d{2})').firstMatch(filename);
        if (m1 != null) {
          final y = int.tryParse(m1.group(1)!);
          final mo = int.tryParse(m1.group(2)!);
          final d = int.tryParse(m1.group(3)!);
          if (y != null && mo != null && d != null && y >= 2000 && mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
            try {
              return DateTime(y, mo, d);
            } catch (_) {}
          }
        }
        final m2 = RegExp(r'(\d{4})[-_](\d{2})[-_](\d{2})').firstMatch(filename);
        if (m2 != null) {
          final y = int.tryParse(m2.group(1)!);
          final mo = int.tryParse(m2.group(2)!);
          final d = int.tryParse(m2.group(3)!);
          if (y != null && mo != null && d != null && y >= 2000 && mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
            try {
              return DateTime(y, mo, d);
            } catch (_) {}
          }
        }
        return null;
      }

      // Map image filenames to sender/date metadata if referenced in chat text
      final mediaMap = <String, Map<String, dynamic>>{};
      if (chatText != null && chatText.isNotEmpty) {
        final lines = chatText.split('\n');
        final waLineRegex = RegExp(
          r'^(?:\[?(\d{1,2}[\/\.-]\d{1,2}[\/\.-]\d{2,4}),?\s+([\d:.]+)(?:\s*([aApP][mM]|\u202F[aApP][mM]))?\]?\s*(?:-|\s*:)?\s*([^:\n]+?):\s*)(.*)$',
          caseSensitive: false,
        );

        DateTime? lastKnownDate;
        String? lastKnownSender;

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          final m = waLineRegex.firstMatch(trimmed);
          String? sender;
          DateTime? parsedDate;
          String? shift;
          String content = trimmed;

          if (m != null) {
            final dateStr = m.group(1);
            final timeStr = m.group(2);
            final ampmStr = m.group(3);
            sender = m.group(4)?.trim();
            content = m.group(5)?.trim() ?? '';

            if (dateStr != null) {
              final clean = dateStr.replaceAll(RegExp(r'[^\d/\.-]'), '');
              final parts = clean.split(RegExp(r'[/.-]'));
              if (parts.length >= 2) {
                final d = int.tryParse(parts[0]);
                final mo = int.tryParse(parts[1]);
                var y = parts.length >= 3 ? int.tryParse(parts[2]) : DateTime.now().year;
                if (y != null && y < 100) y = 2000 + y;
                if (d != null && mo != null && y != null) {
                  try {
                    parsedDate = DateTime(y, mo, d);
                    lastKnownDate = parsedDate;
                  } catch (_) {}
                }
              }
            }

            if (timeStr != null) {
              final hourPart = int.tryParse(timeStr.split(':').first) ?? 0;
              final isPm = ampmStr != null
                  ? ampmStr.toUpperCase().contains('P')
                  : hourPart >= 12;
              final effectiveHour = (isPm && hourPart < 12) ? hourPart + 12 : hourPart;
              if (effectiveHour >= 19 || effectiveHour <= 3) {
                shift = 'Dear 8 PM';
              } else if (effectiveHour >= 15) {
                shift = 'Dear 6 PM';
              } else {
                shift = 'Dear 1 PM';
              }
            }

            if (sender != null && sender.isNotEmpty) {
              lastKnownSender = sender;
            }
          }

          // Identify which image is referenced in this chat line by matching filename
          for (final imgFile in rawImageFiles) {
            final baseName = imgFile.name.split('/').last.split('\\').last;
            final nameNoExt = baseName.contains('.')
                ? baseName.substring(0, baseName.lastIndexOf('.'))
                : baseName;

            if (content.contains(baseName) ||
                trimmed.contains(baseName) ||
                (nameNoExt.length > 5 && (content.contains(nameNoExt) || trimmed.contains(nameNoExt)))) {
              mediaMap[baseName] = {
                'sender': sender ?? lastKnownSender,
                'date': parsedDate ?? lastKnownDate,
                'shift': shift,
              };
            }
          }
        }
      }

      final List<WhatsAppZipMediaItem> mediaItems = [];
      for (final imgFile in rawImageFiles) {
        final baseName = imgFile.name.split('/').last.split('\\').last;
        final rawBytes = imgFile.content as List<int>;
        final meta = mediaMap[baseName];

        final effectiveDate = meta?['date'] as DateTime? ?? extractDateFromFilename(baseName);

        mediaItems.add(
          WhatsAppZipMediaItem(
            filename: baseName,
            bytes: Uint8List.fromList(rawBytes),
            sender: meta?['sender'] as String?,
            date: effectiveDate,
            shift: meta?['shift'] as String?,
          ),
        );
      }

      return WhatsAppZipResult(
        chatText: chatText,
        mediaImages: mediaItems,
        totalFiles: archive.files.length,
        chatFileName: chatFileName,
      );
    } catch (e) {
      debugPrint('⚠️ [WHATSAPP ZIP SERVICE ERROR] $e');
      return WhatsAppZipResult(
        chatText: null,
        mediaImages: [],
        totalFiles: 0,
      );
    }
  }
}
