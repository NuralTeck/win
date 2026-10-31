import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/utils/formatters.dart';
import '../viewmodels/draws_viewmodel.dart';
import '../../shared/models/draw_model.dart';
import '../models/lottery_sambad_result_model.dart';
import '../models/winning_claim_model.dart';
import '../utils/lottery_result_parser.dart';
import '../services/pdf_result_parser_service.dart';
import '../../bookings/viewmodels/ticket_sales_viewmodel.dart';

class DrawsScreen extends ConsumerWidget {
  const DrawsScreen({super.key});

  // ─────────────────────────────────────────────────────────────────────────
  // PDF UPLOAD DIALOG
  // ─────────────────────────────────────────────────────────────────────────
  void _showPdfUploadDialog(BuildContext context, WidgetRef ref, [DrawModel? targetDraw]) {
    final state = ref.read(drawsViewModelProvider);
    DrawModel? selectedDraw = targetDraw ?? (state.draws.isNotEmpty ? state.draws.first : null);
    final rawTextCtrl = TextEditingController(text: '');
    LotterySambadResultModel parsedResult = LotteryResultParser.parseSambadText(
      rawTextCtrl.text,
      drawId: selectedDraw?.id ?? '',
      drawName: selectedDraw?.drawName ?? 'DEAR MORNING 1 PM',
    );

    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updateParsedResult(String val) {
              setDialogState(() {
                parsedResult = LotteryResultParser.parseSambadText(
                  val,
                  drawId: selectedDraw?.id ?? '',
                  drawName: selectedDraw?.drawName ?? 'DEAR MORNING 1 PM',
                );
              });
            }

            Future<void> pickResultFile() async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['pdf', 'txt', 'csv'],
                  allowMultiple: true,
                  withData: true,
                );
                if (result != null && result.files.isNotEmpty) {
                  if (result.files.length == 1) {
                    final file = result.files.first;
                    // Check if PDF
                    if (file.name.toLowerCase().endsWith('.pdf') && file.path != null) {
                      final model = await PdfResultParserService.instance.parseSingleFile(
                        filePath: file.path!,
                        fileBytes: file.bytes,
                        defaultShift: selectedDraw?.drawName,
                      );
                      if (model != null) {
                        int winnerCount = 0;
                        if (selectedDraw != null) {
                          final soldTickets = ref.read(ticketSalesViewModelProvider).sales;
                          final winners = ref.read(drawsViewModelProvider.notifier).publishResultAndCheckWinners(selectedDraw!.id, model, soldTickets);
                          winnerCount = winners.length;
                        } else {
                          await DatabaseService.instance.insertLotteryResult(model);
                        }

                        // Close popup dialog immediately so user is not blocked
                        if (dialogCtx.mounted && Navigator.of(dialogCtx).canPop()) {
                          Navigator.of(dialogCtx).pop();
                        }

                        messenger.showSnackBar(SnackBar(
                          content: Text('✅ PDF "${file.name}" scanned & published (${model.fifthPrizeNumbers.length} prizes, $winnerCount winners)!'),
                          backgroundColor: AppColors.success,
                          duration: const Duration(seconds: 4),
                        ));
                        return;
                      }
                    }

                    // Plain text / CSV fallback
                    String content = '';
                    if (file.bytes != null) {
                      content = utf8.decode(file.bytes!, allowMalformed: true);
                    } else if (file.path != null) {
                      content = await File(file.path!).readAsString();
                    }
                    if (content.isNotEmpty) {
                      rawTextCtrl.text = content;
                      updateParsedResult(content);
                      messenger.showSnackBar(SnackBar(
                        content: Text('File "${file.name}" loaded successfully!'),
                        backgroundColor: AppColors.success,
                      ));
                    }
                  } else {
                    // Batch scan multiple PDFs
                    final report = await PdfResultParserService.instance.parseAndSaveMultipleFiles(
                      files: result.files,
                      defaultShift: selectedDraw?.drawName,
                    );

                    // Close popup dialog immediately
                    if (dialogCtx.mounted && Navigator.of(dialogCtx).canPop()) {
                      Navigator.of(dialogCtx).pop();
                    }

                    if (report.parsedResults.isNotEmpty) {
                      messenger.showSnackBar(SnackBar(
                        content: Text('✅ Scanned & saved ${report.successCount} PDFs! Total Winners: ${report.totalWinnersFound}'),
                        backgroundColor: AppColors.success,
                        duration: const Duration(seconds: 4),
                      ));
                    } else {
                      messenger.showSnackBar(SnackBar(
                        content: const Text('⚠️ Could not extract results from the selected files.'),
                        backgroundColor: AppColors.warning,
                      ));
                    }
                  }
                }
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                  content: Text('Error picking file: $e'),
                  backgroundColor: AppColors.error,
                ));
              }
            }

            final bool hasContent = rawTextCtrl.text.trim().isNotEmpty;

            return AlertDialog(
              backgroundColor: AppColors.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: AppDecorations.radiusLg,
                side: const BorderSide(color: AppColors.border),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.tertiary.withAlpha(40),
                      borderRadius: AppDecorations.radiusDefault,
                    ),
                    child: const Icon(Icons.picture_as_pdf, color: AppColors.tertiary),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload PDF & Auto-Extract Result', style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold)),
                      Text('Official Lottery Sambad / Nagaland State Result Parser & Winner Engine', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select Target Draw Scheme *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: AppDecorations.radiusDefault,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<DrawModel>(
                            value: selectedDraw,
                            isExpanded: true,
                            dropdownColor: AppColors.surfaceContainerHigh,
                            style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                            items: state.draws.map((d) => DropdownMenuItem<DrawModel>(
                              value: d,
                              child: Text('${d.drawCode} — ${d.drawName} (${d.status.name.toUpperCase()})'),
                            )).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() { selectedDraw = val; updateParsedResult(rawTextCtrl.text); });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: pickResultFile,
                            icon: const Icon(Icons.folder_open, size: 18),
                            label: const Text('SELECT PDF / TXT FILE', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusDefault),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () { rawTextCtrl.clear(); updateParsedResult(''); },
                            icon: const Icon(Icons.cleaning_services_outlined, size: 16, color: AppColors.warning),
                            label: const Text('CLEAR TEXT', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.warning),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusDefault),
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () { rawTextCtrl.text = LotteryResultParser.sampleSambadResultText; updateParsedResult(rawTextCtrl.text); },
                            icon: const Icon(Icons.description, size: 14, color: AppColors.textSecondary),
                            label: const Text('Load Sample Demo Text', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text('PDF Raw Text Content / Paste Result Sheet:', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: rawTextCtrl,
                        maxLines: 5,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Click "SELECT PDF / TXT FILE" above or paste official result text here...',
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                          border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                        ),
                        onChanged: updateParsedResult,
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: AppDecorations.radiusDefault,
                          border: Border.all(color: hasContent ? AppColors.primary.withAlpha(120) : AppColors.border, width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('⚡ AUTO-EXTRACTED SAMBAD RESULT PREVIEW', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: hasContent ? AppColors.primary : AppColors.textSecondary, letterSpacing: 1.1)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: hasContent ? AppColors.success.withAlpha(30) : AppColors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: hasContent ? AppColors.success : AppColors.border),
                                  ),
                                  child: Text(hasContent ? 'VERIFIED PARSER' : 'WAITING FOR FILE', style: TextStyle(color: hasContent ? AppColors.success : AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const Divider(color: AppColors.border, height: 20),
                            if (!hasContent)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      const Icon(Icons.upload_file, size: 36, color: AppColors.textSecondary),
                                      const SizedBox(height: 8),
                                      Text('No result text or file loaded yet.', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text('Click "SELECT PDF / TXT FILE" above to choose a result file or paste text.', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                                    ],
                                  ),
                                ),
                              )
                            else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.tertiary)),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('🥇 1ST PRIZE (₹1 CRORE)', style: AppTypography.labelSm.copyWith(color: AppColors.tertiary, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          Text(parsedResult.firstPrize, style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: 1.5)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.primary)),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('🎟️ CONSOLATION PRIZE (₹1,000)', style: AppTypography.labelSm.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          Text(parsedResult.consolationPrize, style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: 1.5)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text('🥈 2nd Prize (₹9,000 — 10 Numbers):', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8, runSpacing: 6,
                                children: parsedResult.secondPrizeNumbers.map((n) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.border)),
                                  child: Text(n, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.textPrimary)),
                                )).toList(),
                              ),
                              const SizedBox(height: 10),
                              Text('🥉 3rd Prize (₹500 — 10 Numbers):', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(parsedResult.thirdPrizeNumbers.join('   '), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () { if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx); },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: !hasContent ? null : () {
                    if (selectedDraw == null) return;
                    final soldTickets = ref.read(ticketSalesViewModelProvider).sales;
                    final winners = ref.read(drawsViewModelProvider.notifier).publishResultAndCheckWinners(selectedDraw!.id, parsedResult, soldTickets);
                    if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
                    _showWinnersClaimDialog(context, selectedDraw!.drawName, winners);
                  },
                  icon: const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('PUBLISH & CHECK WINNERS', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MANUAL RESULT ENTRY FORM  (Chip-based number input)
  // ─────────────────────────────────────────────────────────────────────────
  void _showManualResultEntryDialog(BuildContext context, WidgetRef ref, [DrawModel? targetDraw]) {
    final state = ref.read(drawsViewModelProvider);
    DrawModel? selectedDraw = targetDraw ?? (state.draws.isNotEmpty ? state.draws.first : null);

    final firstPrizeSeriesCtrl = TextEditingController();
    final firstPrizeNumberCtrl = TextEditingController();
    final consolationCtrl      = TextEditingController();

    final List<String> p2Numbers = [];
    final List<String> p3Numbers = [];
    final List<String> p4Numbers = [];
    final List<String> p5Numbers = [];

    final p2InputCtrl = TextEditingController();
    final p3InputCtrl = TextEditingController();
    final p4InputCtrl = TextEditingController();
    final p5InputCtrl = TextEditingController();

    final f1series = FocusNode();
    final f1number = FocusNode();
    final fConsol  = FocusNode();
    final f2Input  = FocusNode();
    final f3Input  = FocusNode();
    final f4Input  = FocusNode();
    final f5Input  = FocusNode();

    String? errorMsg;

    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {

            // ── Section label with count badge ──────────────────────────
            Widget sectionLabel(String title, String prizeAmt, int count, {int? expected}) {
              return Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Row(
                  children: [
                    Text(title, style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                      child: Text(prizeAmt, style: AppTypography.labelSm.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: count > 0 ? AppColors.success.withAlpha(25) : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: count > 0 ? AppColors.success : AppColors.border),
                      ),
                      child: Text(
                        expected != null ? '$count / $expected numbers' : '$count numbers',
                        style: AppTypography.labelSm.copyWith(color: count > 0 ? AppColors.success : AppColors.textSecondary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            }

            // ── Chip input widget ────────────────────────────────────────
            Widget chipInputField({
              required List<String> chips,
              required TextEditingController ctrl,
              required FocusNode focusNode,
              required int digitLen,
              required String hint,
              Color chipColor = AppColors.primary,
              int maxChips = 999,
            }) {
              void addChip(String raw) {
                if (chips.length >= maxChips) return; // Limit enforce
                final parts = raw.trim().split(RegExp(r'[\s,]+'));
                bool added = false;
                for (final part in parts) {
                  if (chips.length >= maxChips) break;
                  final val = part.trim();
                  if (val.length == digitLen && !chips.contains(val)) {
                    chips.add(val);
                    added = true;
                  }
                }
                if (added) { ctrl.clear(); setDialogState(() {}); }
              }

              final bool limitReached = chips.length >= maxChips;

              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: AppDecorations.radiusDefault,
                  border: Border.all(color: limitReached ? AppColors.success.withAlpha(120) : AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (chips.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 6, runSpacing: 6,
                          children: chips.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final num = entry.value;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: chipColor.withAlpha(30),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: chipColor.withAlpha(120)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(num, style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 13, color: chipColor, letterSpacing: 1.5)),
                                  const SizedBox(width: 5),
                                  GestureDetector(
                                    onTap: () => setDialogState(() => chips.removeAt(idx)),
                                    child: Icon(Icons.close, size: 14, color: chipColor),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    if (limitReached)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                            const SizedBox(width: 6),
                            Text(
                              'Max $maxChips numbers entered — limit complete! ✅',
                              style: AppTypography.labelSm.copyWith(color: AppColors.success, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: ctrl,
                              focusNode: focusNode,
                              maxLength: digitLen,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: AppColors.textPrimary, letterSpacing: 2, fontWeight: FontWeight.bold),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (val) {
                                if (chips.length < maxChips) addChip(val);
                                focusNode.requestFocus();
                              },
                              onChanged: (val) {
                                if (chips.length < maxChips && val.trim().length == digitLen) addChip(val);
                              },
                              decoration: InputDecoration(
                                hintText: hint,
                                hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                counterText: '',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              if (chips.length < maxChips) addChip(ctrl.text);
                            },
                            icon: const Icon(Icons.add_circle, size: 16),
                            label: const Text('Add'),
                            style: TextButton.styleFrom(foregroundColor: chipColor, padding: const EdgeInsets.symmetric(horizontal: 8)),
                          ),
                        ],
                      ),
                    if (!limitReached)
                      Text('$digitLen-digit number → Enter ya Add button dabaayein', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              );
            }

            // ── Publish ──────────────────────────────────────────────────
            void onPublish() {
              setDialogState(() => errorMsg = null);
              if (firstPrizeSeriesCtrl.text.trim().isEmpty || firstPrizeNumberCtrl.text.trim().isEmpty) {
                setDialogState(() => errorMsg = '1st Prize: Series aur Number dono required hain.');
                return;
              }
              if (consolationCtrl.text.trim().isEmpty) {
                setDialogState(() => errorMsg = 'Consolation Prize number required hai.');
                return;
              }
              final now = DateTime.now();
              final result = LotterySambadResultModel(
                drawId:             selectedDraw?.id ?? '',
                drawName:           selectedDraw?.drawName ?? '',
                drawDateStr:        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}',
                drawTimeStr:        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                firstPrize:         '${firstPrizeSeriesCtrl.text.trim().toUpperCase()} ${firstPrizeNumberCtrl.text.trim()}',
                consolationPrize:   consolationCtrl.text.trim(),
                secondPrizeNumbers: List<String>.from(p2Numbers),
                thirdPrizeNumbers:  List<String>.from(p3Numbers),
                fourthPrizeNumbers: List<String>.from(p4Numbers),
                fifthPrizeNumbers:  List<String>.from(p5Numbers),
                publishedAt:        now,
              );
              final soldTickets = ref.read(ticketSalesViewModelProvider).sales;
              final winners = ref.read(drawsViewModelProvider.notifier).publishResultAndCheckWinners(selectedDraw!.id, result, soldTickets);
              if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
              _showWinnersClaimDialog(context, selectedDraw!.drawName, winners);
            }

            return AlertDialog(
              backgroundColor: AppColors.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg, side: const BorderSide(color: AppColors.border)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.success.withAlpha(40), borderRadius: AppDecorations.radiusDefault),
                    child: const Icon(Icons.edit_note, color: AppColors.success),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Manual Result Entry', style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold)),
                      Text('Number type karein → Enter dabaayen → chip ban jaayega', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 740,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Draw Selector
                      Text('Target Draw Scheme *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: AppDecorations.radiusDefault, border: Border.all(color: AppColors.border)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<DrawModel>(
                            value: selectedDraw,
                            isExpanded: true,
                            dropdownColor: AppColors.surfaceContainerHigh,
                            style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                            items: state.draws.map((d) => DropdownMenuItem<DrawModel>(value: d, child: Text('${d.drawCode} — ${d.drawName} (${d.status.name.toUpperCase()})'))).toList(),
                            onChanged: (val) { if (val != null) setDialogState(() => selectedDraw = val); },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 1st Prize
                      Row(children: [
                        Text('🥇 1st Prize', style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.tertiary.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                          child: Text('₹1,00,00,000', style: AppTypography.labelSm.copyWith(color: AppColors.tertiary, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: firstPrizeSeriesCtrl, focusNode: f1series, maxLength: 6,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => FocusScope.of(ctx).requestFocus(f1number),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.bold, letterSpacing: 2),
                            decoration: const InputDecoration(labelText: 'Series', hintText: '83L', counterText: '', filled: true, fillColor: AppColors.surfaceContainerLow, border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: firstPrizeNumberCtrl, focusNode: f1number, maxLength: 6,
                            keyboardType: TextInputType.number, textInputAction: TextInputAction.next,
                            onSubmitted: (_) => FocusScope.of(ctx).requestFocus(fConsol),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 22, color: AppColors.tertiary, fontWeight: FontWeight.w900, letterSpacing: 4),
                            decoration: const InputDecoration(labelText: '5-Digit Number', hintText: '28311', counterText: '', filled: true, fillColor: AppColors.surfaceContainerLow, border: OutlineInputBorder()),
                          ),
                        ),
                      ]),

                      // Consolation Prize
                      const SizedBox(height: 16),
                      Row(children: [
                        Text('🎟️ Consolation Prize', style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.primary.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                          child: Text('₹1,000', style: AppTypography.labelSm.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                        controller: consolationCtrl, focusNode: fConsol, maxLength: 5,
                        keyboardType: TextInputType.number, textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(ctx).requestFocus(f2Input),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 18, color: AppColors.primary, fontWeight: FontWeight.bold, letterSpacing: 3),
                        decoration: const InputDecoration(hintText: '28311', counterText: '', filled: true, fillColor: AppColors.surfaceContainerLow, border: OutlineInputBorder()),
                      ),

                      // 2nd Prize Chips
                      sectionLabel('🥈 2nd Prize', '₹9,000', p2Numbers.length, expected: 10),
                      chipInputField(chips: p2Numbers, ctrl: p2InputCtrl, focusNode: f2Input, digitLen: 5, hint: '5-digit number type karein...', chipColor: const Color(0xFF64B5F6), maxChips: 10),

                      // 3rd Prize Chips
                      sectionLabel('🥉 3rd Prize', '₹500', p3Numbers.length, expected: 10),
                      chipInputField(chips: p3Numbers, ctrl: p3InputCtrl, focusNode: f3Input, digitLen: 4, hint: '4-digit number type karein...', chipColor: const Color(0xFF81C784), maxChips: 10),

                      // 4th Prize Chips
                      sectionLabel('🏅 4th Prize', '₹250', p4Numbers.length, expected: 10),
                      chipInputField(chips: p4Numbers, ctrl: p4InputCtrl, focusNode: f4Input, digitLen: 4, hint: '4-digit number type karein...', chipColor: const Color(0xFFFFB74D), maxChips: 10),

                      // 5th Prize Chips
                      sectionLabel('🏅 5th Prize', '₹120', p5Numbers.length, expected: 100),
                      chipInputField(chips: p5Numbers, ctrl: p5InputCtrl, focusNode: f5Input, digitLen: 4, hint: '4-digit number type karein...', chipColor: const Color(0xFFBA68C8), maxChips: 100),

                      // Error
                      if (errorMsg != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: AppColors.error.withAlpha(25), borderRadius: AppDecorations.radiusDefault, border: Border.all(color: AppColors.error.withAlpha(100))),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: AppColors.error, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(errorMsg!, style: AppTypography.bodySm.copyWith(color: AppColors.error))),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () { if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx); }, child: const Text('Cancel')),
                ElevatedButton.icon(
                  onPressed: onPublish,
                  icon: const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('PUBLISH & CHECK WINNERS', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WINNER CLAIMS DIALOG
  // ─────────────────────────────────────────────────────────────────────────
  void _showWinnersClaimDialog(BuildContext context, String drawName, List<WinningClaimModel> claims) {
    final double totalPayout = claims.fold(0.0, (sum, c) => sum + c.prizeAmount);

    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg, side: const BorderSide(color: AppColors.border)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.success.withAlpha(40), borderRadius: AppDecorations.radiusDefault),
                child: const Icon(Icons.emoji_events, color: AppColors.success),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Automated Winner Claims Settlement', style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold)),
                  Text('$drawName — ${claims.length} Winning Tickets Identified', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ]),
            IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () { if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx); }),
          ],
        ),
        content: SizedBox(
          width: 780,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: AppDecorations.radiusDefault, border: Border.all(color: AppColors.success)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TOTAL WINNING TICKET PAYOUT', style: AppTypography.labelSm.copyWith(color: AppColors.success, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(Formatters.formatIndianCurrency(totalPayout), style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.success.withAlpha(30), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.success)),
                        child: Text('${claims.length} WINNERS FOUND', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (claims.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text('No sold tickets matched winning prize numbers for this draw.', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary))),
                  )
                else
                  Table(
                    columnWidths: const {0: FlexColumnWidth(1.8), 1: FlexColumnWidth(1.5), 2: FlexColumnWidth(2.0), 3: FlexColumnWidth(1.8), 4: FlexColumnWidth(1.8)},
                    border: const TableBorder(horizontalInside: BorderSide(color: AppColors.border, width: 0.8)),
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: AppColors.surfaceContainerLow),
                        children: [
                          _tableCell('Prize Tier', isHeader: true),
                          _tableCell('Winning No', isHeader: true),
                          _tableCell('Ticket Series & No', isHeader: true),
                          _tableCell('Customer', isHeader: true),
                          _tableCell('Prize Amount', isHeader: true, alignment: Alignment.centerRight),
                        ],
                      ),
                      ...claims.map((claim) => TableRow(children: [
                        _tableCell(claim.prizeTier, isBold: true, color: AppColors.primary),
                        _tableCell(claim.winningNumber, isBold: true, color: AppColors.tertiary),
                        _tableCell('${claim.ticketSeries} ${claim.ticketNumber}', isBold: true),
                        _tableCell(claim.buyerName, color: AppColors.textSecondary),
                        _tableCell(Formatters.formatIndianCurrency(claim.prizeAmount), isBold: true, color: AppColors.success, alignment: Alignment.centerRight),
                      ])),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Winning claims settlement receipts generated & ready for disbursement!'), backgroundColor: AppColors.success));
            },
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('DISBURSE & CLOSE SETTLEMENT', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          ),
        ],
      ),
    );
  }

  Widget _tableCell(String text, {bool isHeader = false, bool isBold = false, Color? color, Alignment alignment = Alignment.centerLeft}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Align(
        alignment: alignment,
        child: Text(
          text,
          style: isHeader
              ? AppTypography.labelSm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)
              : AppTypography.bodySm.copyWith(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? AppColors.textPrimary),
        ),
      ),
    );
  }

  void _showViewResultSheetDialog(BuildContext context, LotterySambadResultModel result) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg, side: const BorderSide(color: AppColors.border)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NAGALAND STATE LOTTERIES', style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.w900, color: AppColors.primary)),
                Text('${result.drawName} • Draw Date: ${result.drawDateStr} • Time: ${result.drawTimeStr}', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(icon: const Icon(Icons.close, color: AppColors.textSecondary), onPressed: () { if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx); }),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: AppDecorations.radiusDefault, border: Border.all(color: AppColors.border)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('1st Prize: ₹1,00,00,000 /-', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold, color: AppColors.tertiary)),
                      Text(result.firstPrize, style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.w900, color: AppColors.tertiary, letterSpacing: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: AppDecorations.radiusDefault),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Consolation Prize: ₹1,000 /-', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                      Text(result.consolationPrize, style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('2nd Prize ₹9,000 / -', style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 6, children: result.secondPrizeNumbers.map((n) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.border)),
                  child: Text(n, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.textPrimary)),
                )).toList()),
                const SizedBox(height: 16),
                Text('3rd Prize ₹500 / -', style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(result.thirdPrizeNumbers.join('   '), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14)),
                const SizedBox(height: 14),
                Text('4th Prize ₹250 / -', style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(result.fourthPrizeNumbers.join('   '), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(drawsViewModelProvider);
    final notifier = ref.read(drawsViewModelProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Draws & Lottery Schemes', style: AppTypography.headlineLg.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Manage active, scheduled and official Lottery Sambad results', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
                ],
              ),
              Row(children: [
                AppSecondaryButton(label: 'Draw Times & Shifts', icon: Icons.access_time, onPressed: () => context.go(AppConstants.routeDrawTimes)),
                const SizedBox(width: 12),
                AppSecondaryButton(label: 'Enter Result Manually', icon: Icons.edit_note, onPressed: () => _showManualResultEntryDialog(context, ref)),
                const SizedBox(width: 12),
                AppSecondaryButton(label: 'Upload Result PDF', icon: Icons.picture_as_pdf, onPressed: () => _showPdfUploadDialog(context, ref)),
                const SizedBox(width: 12),
                AppPrimaryButton(label: 'New Draw Scheme', icon: Icons.add, onPressed: () {}),
              ]),
            ],
          ),
          const SizedBox(height: 24),

          // ── Summary Bar ──────────────────────────────────────────────────
          Row(children: [
            _SummaryChip(icon: Icons.play_circle_outline, label: 'Open', value: state.draws.where((d) => d.status == DrawStatus.open).length.toString(), color: AppColors.success),
            const SizedBox(width: 12),
            _SummaryChip(icon: Icons.lock_clock, label: 'Closed / Pending', value: state.draws.where((d) => d.status == DrawStatus.closed).length.toString(), color: AppColors.warning),
            const SizedBox(width: 12),
            _SummaryChip(icon: Icons.check_circle_outline, label: 'Completed', value: state.draws.where((d) => d.status == DrawStatus.completed).length.toString(), color: AppColors.primary),
            const SizedBox(width: 12),
            _SummaryChip(icon: Icons.currency_rupee, label: 'Total Prize Pool', value: Formatters.formatIndianCurrency(state.draws.fold(0.0, (sum, d) => sum + d.prizePool)), color: AppColors.tertiary),
          ]),
          const SizedBox(height: 24),

          // ── Search & Filters ─────────────────────────────────────────────
          Row(children: [
            SizedBox(width: 340, child: AppSearchField(hintText: 'Search draw name, code, district...', onChanged: notifier.setSearchQuery)),
            const SizedBox(width: 16),
            _DrawFilterChip(label: 'All', isSelected: state.selectedStatus == null, onTap: () => notifier.setStatusFilter(null)),
            const SizedBox(width: 8),
            _DrawFilterChip(label: 'Open', isSelected: state.selectedStatus == DrawStatus.open, onTap: () => notifier.setStatusFilter(DrawStatus.open)),
            const SizedBox(width: 8),
            _DrawFilterChip(label: 'Closed', isSelected: state.selectedStatus == DrawStatus.closed, onTap: () => notifier.setStatusFilter(DrawStatus.closed)),
            const SizedBox(width: 8),
            _DrawFilterChip(label: 'Completed', isSelected: state.selectedStatus == DrawStatus.completed, onTap: () => notifier.setStatusFilter(DrawStatus.completed)),
          ]),
          const SizedBox(height: 20),

          // ── Draws Table ──────────────────────────────────────────────────
          AppDataTable(
            isLoading: state.isLoading,
            columns: const [
              AppTableColumn(label: 'DRAW CODE', width: 120),
              AppTableColumn(label: 'DRAW NAME & SCHEME'),
              AppTableColumn(label: 'TICKET PRICE', width: 120),
              AppTableColumn(label: 'TICKETS SOLD', width: 130),
              AppTableColumn(label: 'PRIZE POOL', width: 130),
              AppTableColumn(label: 'STATUS', width: 110),
              AppTableColumn(label: 'DRAW DATE', width: 150),
              AppTableColumn(label: 'ACTIONS', width: 140, alignment: Alignment.centerRight),
            ],
            rows: state.filteredDraws.map((d) {
              final result = state.resultsMap[d.id];
              final claims = state.winningClaimsMap[d.id] ?? [];
              return [
                Text(d.drawCode, style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(d.drawName, style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                    Text('${d.schemeType} • ${d.conductedBy} • ${d.district}', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary.withAlpha(150)), overflow: TextOverflow.ellipsis),
                    if (result != null) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF1E1B4B), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF818CF8))),
                        child: Text('🎯 1st Prize Khula: ${result.firstPrize}', style: const TextStyle(color: Color(0xFFA5B4FC), fontWeight: FontWeight.bold, fontSize: 10)),
                      ),
                    ],
                  ],
                ),
                Text('₹${d.ticketPrice.toStringAsFixed(d.ticketPrice % 1 == 0 ? 0 : 2)}', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700, color: AppColors.tertiary)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${Formatters.formatNumber(d.ticketsSold)} / ${Formatters.formatNumber(d.totalTickets)}', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ClipRRect(
                      borderRadius: AppDecorations.radiusPill,
                      child: LinearProgressIndicator(
                        value: d.salesProgress, minHeight: 4,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        valueColor: AlwaysStoppedAnimation<Color>(d.salesProgress > 0.8 ? AppColors.success : (d.salesProgress > 0.5 ? AppColors.primary : AppColors.warning)),
                      ),
                    ),
                  ],
                ),
                Text(Formatters.formatIndianCurrency(d.prizePool), style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                StatusBadge.fromStatus(d.status.name),
                Text(Formatters.formatDateTime(d.drawDate), style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (d.status == DrawStatus.completed && result != null) ...[
                      IconButton(icon: const Icon(Icons.emoji_events, size: 18, color: AppColors.tertiary), tooltip: 'View Sambad Result Sheet', onPressed: () => _showViewResultSheetDialog(context, result)),
                      IconButton(icon: const Icon(Icons.verified, size: 18, color: AppColors.success), tooltip: 'View Winner Claims (${claims.length})', onPressed: () => _showWinnersClaimDialog(context, d.drawName, claims)),
                    ] else
                      IconButton(icon: const Icon(Icons.upload_file, size: 18, color: AppColors.primary), tooltip: 'Upload Result PDF & Match Winners', onPressed: () => _showPdfUploadDialog(context, ref, d)),
                  ],
                ),
              ];
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ──────────────────────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _SummaryChip({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: AppDecorations.radiusDefault, border: Border.all(color: color.withAlpha(60), width: 1)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppTypography.labelSm.copyWith(color: color.withAlpha(200))),
              Text(value, style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DrawFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _DrawFilterChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppDecorations.radiusPill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerLow,
          borderRadius: AppDecorations.radiusPill,
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: 1),
        ),
        child: Text(
          label,
          style: AppTypography.labelSm.copyWith(
            color: isSelected ? AppColors.onPrimaryContainer : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
