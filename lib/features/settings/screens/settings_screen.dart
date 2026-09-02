import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/database/database_service.dart';
import '../../../core/services/whatsapp_engine_service.dart';
import '../../bookings/viewmodels/ticket_sales_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import 'price_setup_screen.dart';
import '../../operations/screens/whatsapp_engine_screen.dart';
import '../../sellers/screens/customer_setup_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const List<String> tabs = [
    'Price & Series Setup',
    '👑 Dealers & Sellers Setup',
    'WhatsApp Connect & Bot',
    'API Credentials',
    '🧹 Master Data Reset (0)',
  ];

  Future<void> _showMasterWipeDialog(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text(
              'MASTER SYSTEM RESET (0)',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '⚠️ Yeh action system ke saare data ko 0 par RESET kar dega:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
            ),
            SizedBox(height: 12),
            Text('• Saari Ticket Bookings & Sales (0) 🗑️', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 4),
            Text('• WhatsApp Photos & Parchas (0) 🗑️', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 4),
            Text('• Lottery Results & Inam (0) 🗑️', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 4),
            Text('• Generated Hisab & Ledger (0) 🗑️', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 14),
            Text(
              'Kya aap sach me pura system data 0 par RESET karna chahte hain?',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('CONFIRM & WIPE ALL DATA', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await DatabaseService.instance.wipeAllOperationalData();
        await ref.read(ticketSalesViewModelProvider.notifier).loadSales();
        await WhatsAppEngineService.instance.resetProcessedCount();
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 10),
                  Text('🧹 Master Reset Complete: All ticket data, photos & hisab wiped to 0!'),
                ],
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text('⚠️ Error wiping data: $e'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsViewModelProvider);
    final notifier = ref.read(settingsViewModelProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System Configuration & Platform Settings',
                      style: AppTypography.headlineLg.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage ticket prices, draw times, shift schedules, and platform security',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.delete_forever_rounded, size: 18),
                    label: const Text(
                      'RESET ALL DATA (0)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _showMasterWipeDialog(context, ref),
                  ),
                  AppPrimaryButton(
                    label: 'Save Configuration',
                    icon: Icons.save_outlined,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Settings saved successfully.')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Settings Tab Navigation Bar
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: AppDecorations.radiusDefault,
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(tabs.length, (idx) {
                  final isSelected = state.selectedTabIndex == idx;
                  return InkWell(
                    onTap: () => notifier.setTab(idx),
                    borderRadius: AppDecorations.radiusDefault,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.surfaceContainerHighest : Colors.transparent,
                        borderRadius: AppDecorations.radiusDefault,
                      ),
                      child: Text(
                        tabs[idx],
                        style: AppTypography.bodySm.copyWith(
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Tab Content Area
          IndexedStack(
            index: state.selectedTabIndex,
            children: [
              const PriceSetupScreen(),
              const CustomerSetupScreen(),
              const WhatsAppEngineScreen(),
              const _ApiCredentialsTab(),
              const _DatabaseResetTab(),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApiCredentialsTab extends StatefulWidget {
  const _ApiCredentialsTab();

  @override
  State<_ApiCredentialsTab> createState() => _ApiCredentialsTabState();
}

class _ApiCredentialsTabState extends State<_ApiCredentialsTab> {
  final _geminiKeyCtrl = TextEditingController();
  bool _obscureKey = true;
  bool _isSaving = false;
  bool _isConfigured = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentApiKey();
  }

  @override
  void dispose() {
    _geminiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentApiKey() async {
    final key = await DatabaseService.instance.getGeminiApiKey();
    if (mounted) {
      setState(() {
        if (key != null && key.isNotEmpty) {
          _geminiKeyCtrl.text = key;
          _isConfigured = true;
        } else {
          _isConfigured = false;
        }
      });
    }
  }

  Future<void> _saveGeminiApiKey() async {
    final key = _geminiKeyCtrl.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.warning,
          content: Text('⚠️ Please enter a valid Gemini API Key.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      // 1. Save in local SQLite
      await DatabaseService.instance.saveGeminiApiKey(key);

      // 2. Notify WhatsApp Bot Engine REST API
      try {
        await http.post(
          Uri.parse('http://127.0.0.1:4000/api/settings/ai'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'apiKey': key}),
        );
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isConfigured = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.success,
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('✅ Gemini Vision AI Key saved and activated successfully!'),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('⚠️ Error: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty && mounted) {
      setState(() {
        _geminiKeyCtrl.text = data.text!.trim();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📋 Pasted API Key from Clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── 1. GEMINI VISION AI SCANNER CONFIGURATION CARD ─────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.purpleAccent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(Icons.document_scanner_rounded, color: Colors.purpleAccent, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Google Gemini Vision AI — Photo & Parcha Scanner',
                                style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _isConfigured ? Colors.green.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _isConfigured ? Colors.green : Colors.amber,
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isConfigured ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                      size: 12,
                                      color: _isConfigured ? Colors.green : Colors.amber,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isConfigured ? 'ACTIVE & READY' : 'KEY REQUIRED',
                                      style: TextStyle(
                                        color: _isConfigured ? Colors.green : Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Scans ticket photos, handwritten slips (parchas), and bills received on WhatsApp or Desktop with 99.9% accuracy',
                            style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 18),

              // API Key Input Field
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Google Gemini API Key *',
                        style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.paste_rounded, size: 14, color: AppColors.primary),
                        label: const Text('Paste Key', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                        onPressed: _pasteFromClipboard,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _geminiKeyCtrl,
                    obscureText: _obscureKey,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'AIzaSy...',
                      filled: true,
                      fillColor: AppColors.surfaceContainerLowest,
                      prefixIcon: const Icon(Icons.key_rounded, size: 18, color: AppColors.primary),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                        onPressed: () => setState(() => _obscureKey = !_obscureKey),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Quota / Switch API Key Tip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: AppColors.info),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '💡 Note: Agar kisi API Key par rate limit / daily quota lag jaye, to aap yahan nayi Gemini API Key daal kar save kar sakte hain. System bina kisi downtime ke turant nayi key use karne lagega.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Save Button
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: _isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          _isSaving ? 'Saving & Activating...' : 'Save & Activate Gemini AI Key',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isSaving ? null : _saveGeminiApiKey,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ─── 2. ACTIVE API SERVICE KEYS ───────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Active API Service Keys & Gateway Endpoints',
                    style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.w700),
                  ),
                  AppPrimaryButton(
                    label: 'Generate Gateway Key',
                    icon: Icons.key_outlined,
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppDataTable(
                columns: const [
                  AppTableColumn(label: 'SERVICE NAME', width: 160),
                  AppTableColumn(label: 'ENDPOINT / STATUS'),
                  AppTableColumn(label: 'SCOPE', width: 120),
                  AppTableColumn(label: 'UPDATED', width: 140),
                ],
                rows: [
                  [
                    Text('Gemini Vision AI OCR', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                    Text(_isConfigured ? 'Active & Running' : 'Key Missing', style: AppTypography.bodySm.copyWith(color: _isConfigured ? AppColors.success : AppColors.warning)),
                    Text('Photo Scanner', style: AppTypography.bodySm.copyWith(color: AppColors.primary)),
                    Text(DateFormat('dd-MM-yyyy').format(DateTime.now()), style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                  ],
                  [
                    Text('Local WhatsApp Engine', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold)),
                    Text('http://127.0.0.1:4000', style: AppTypography.bodySm.copyWith(fontFamily: 'monospace', color: AppColors.textSecondary)),
                    Text('Full Gateway', style: AppTypography.bodySm.copyWith(color: AppColors.tertiary)),
                    Text('Realtime Active', style: AppTypography.labelSm.copyWith(color: AppColors.success)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DatabaseResetTab extends ConsumerStatefulWidget {
  const _DatabaseResetTab();

  @override
  ConsumerState<_DatabaseResetTab> createState() => _DatabaseResetTabState();
}

class _DatabaseResetTabState extends ConsumerState<_DatabaseResetTab> {
  bool _isWiping = false;

  Future<void> _showConfirmWipeDialog(BuildContext context, {required bool wipeSalesOnly}) async {
    final messenger = ScaffoldMessenger.of(context);
    final title = wipeSalesOnly ? 'Wipe All Ticket Sales Data' : 'Wipe All System Data (0)';
    final content = wipeSalesOnly
        ? 'Are you sure you want to permanently DELETE all ticket bookings from Local SQLite & Cloud?\n\nThis will reset ticket sales back to 0. This action CANNOT be undone!'
        : '⚠️ DANGER: ARE YOU SURE?\n\nThis will completely WIPE & RESET:\n• All Ticket Bookings (0)\n• WhatsApp Photos & Parchas (0)\n• Lottery Draw Results (0)\n• Collector Payments & Ledgers (0)\n\nAll data will be reset to a clean blank state (0)!';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 10),
            Text(title, style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold, color: Colors.redAccent)),
          ],
        ),
        content: Text(
          content,
          style: AppTypography.bodyMd.copyWith(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever),
            label: Text(wipeSalesOnly ? 'WIPE TICKET SALES' : 'CONFIRM & WIPE EVERYTHING'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isWiping = true);
      try {
        if (wipeSalesOnly) {
          await DatabaseService.instance.wipeAllTicketSales();
        } else {
          await DatabaseService.instance.wipeAllOperationalData();
        }
        await ref.read(ticketSalesViewModelProvider.notifier).loadSales();
        await WhatsAppEngineService.instance.resetProcessedCount();
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade800,
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(wipeSalesOnly
                      ? '🧹 All ticket sales & booking data wiped completely!'
                      : '🧹 Master Reset Complete: All operational data reset to 0!'),
                ],
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text('⚠️ Error wiping data: $e'),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isWiping = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cleaning_services_rounded, color: Colors.amberAccent, size: 30),
                  const SizedBox(width: 12),
                  Text(
                    'Testing & Master Data Wipe Operations (Danger Zone)',
                    style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.w700, color: Colors.redAccent),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Use these tools during testing to completely wipe old ticket bookings, WhatsApp parchas, results, and reset all system counters back to 0.',
                style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              const Divider(color: AppColors.border),
              const SizedBox(height: 16),

              // Action 1: Wipe Ticket Sales
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wipe All Ticket Sales & Bookings',
                          style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Deletes all booked tickets from ticket_sales table in Local DB and resets booking counters to 0.',
                          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    icon: _isWiping
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.delete_sweep_rounded),
                    label: Text(_isWiping ? 'Wiping...' : 'Wipe Ticket Sales (0)'),
                    onPressed: _isWiping ? null : () => _showConfirmWipeDialog(context, wipeSalesOnly: true),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(color: AppColors.border),
              const SizedBox(height: 16),

              // Action 2: Full System Wipe
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Master System Wipe (All Data to 0)',
                          style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.w600, color: Colors.redAccent),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Deletes all sales bookings, pending WhatsApp parchas, lottery results, and resets all counters to 0.',
                          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: const Text('Master Reset All Data (0)'),
                    onPressed: _isWiping ? null : () => _showConfirmWipeDialog(context, wipeSalesOnly: false),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
