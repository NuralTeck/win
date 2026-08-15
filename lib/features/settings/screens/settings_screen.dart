import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/database/database_service.dart';
import '../../../core/database/supabase_service.dart';
import '../viewmodels/settings_viewmodel.dart';
import 'price_setup_screen.dart';
import 'draw_time_setup_screen.dart';
import '../../operations/screens/whatsapp_engine_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const List<String> tabs = [
    'Price & Series Setup',
    'Draw Times & Shifts',
    'WhatsApp Connect & Bot',
    'General Config',
    'Security & Auth',
    'API Credentials',
    'Database & Wipe Data',
  ];

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
              const DrawTimeSetupScreen(),
              const WhatsAppEngineScreen(),
              _GeneralSettingsTab(state: state, notifier: notifier),
              _SecuritySettingsTab(state: state, notifier: notifier),
              const _ApiCredentialsTab(),
              const _DatabaseResetTab(),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeneralSettingsTab extends StatelessWidget {
  final SettingsState state;
  final SettingsViewModel notifier;

  const _GeneralSettingsTab({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cluster Environment Identifiers',
                style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Cluster Environment Name',
                      hintText: 'OpsCore Production Grid 1',
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: AppTextField(
                      label: 'Primary Region',
                      hintText: 'us-east-1 (Virginia)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const AppTextField(
                label: 'Telemetry Endpoint URL',
                hintText: 'https://telemetry.opscore.internal/v2/ingest',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'System Preferences',
                style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _SwitchRowTile(
                title: 'Real-time Telemetry Streaming',
                subtitle: 'Streams live node metrics to central analytics hub',
                value: state.enableTelemetry,
                onChanged: notifier.toggleTelemetry,
              ),
              const Divider(height: 24, color: AppColors.border),
              _SwitchRowTile(
                title: 'Automated Snapshot Backups',
                subtitle: 'Triggers hourly state snapshots to cloud storage buckets',
                value: state.autoBackup,
                onChanged: notifier.toggleAutoBackup,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SecuritySettingsTab extends StatelessWidget {
  final SettingsState state;
  final SettingsViewModel notifier;

  const _SecuritySettingsTab({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Authentication & Access Policies',
            style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          _SwitchRowTile(
            title: 'Enforce Hardware 2FA / WebAuthn',
            subtitle: 'Require FIDO2 hardware tokens for admin operations',
            value: state.enable2FA,
            onChanged: notifier.toggle2FA,
          ),
          const Divider(height: 24, color: AppColors.border),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Timeout Window',
                      style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Automatically log out idle desktop sessions after specified duration',
                      style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              AppSecondaryButton(
                label: '30 Minutes',
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApiCredentialsTab extends StatelessWidget {
  const _ApiCredentialsTab();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active API Service Keys',
                style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.w700),
              ),
              AppPrimaryButton(
                label: 'Generate New Key',
                icon: Icons.key_outlined,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppDataTable(
            columns: const [
              AppTableColumn(label: 'KEY NAME', width: 140),
              AppTableColumn(label: 'API TOKEN HASH'),
              AppTableColumn(label: 'SCOPE', width: 120),
              AppTableColumn(label: 'CREATED', width: 140),
            ],
            rows: [
              [
                Text('Prod-Gateway-01', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold)),
                Text('opscore_live_89f2a***9128', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
                Text('Full Admin', style: AppTypography.bodySm.copyWith(color: AppColors.primary)),
                Text('2026-05-12', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
              ],
              [
                Text('Analytics-Read', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold)),
                Text('opscore_live_31a90***8421', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
                Text('Read Only', style: AppTypography.bodySm.copyWith(color: AppColors.tertiary)),
                Text('2026-06-01', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SwitchRowTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRowTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
          activeTrackColor: AppColors.primaryContainer,
        ),
      ],
    );
  }
}

class _DatabaseResetTab extends StatefulWidget {
  const _DatabaseResetTab();

  @override
  State<_DatabaseResetTab> createState() => _DatabaseResetTabState();
}

class _DatabaseResetTabState extends State<_DatabaseResetTab> {
  bool _isWiping = false;

  Future<void> _showConfirmWipeDialog(BuildContext context, {required bool wipeSalesOnly}) async {
    final messenger = ScaffoldMessenger.of(context);
    final title = wipeSalesOnly ? 'Wipe All Ticket Sales Data' : 'Wipe All System Data';
    final content = wipeSalesOnly
        ? 'Are you sure you want to permanently DELETE all ticket bookings and sales records from both Supabase Cloud and Local Database?\n\nThis is useful for clean testing. This action CANNOT be undone!'
        : 'Are you sure you want to PERMANENTLY DELETE ALL data (Ticket Sales, Unsold Tickets, etc.) from Cloud and Local DB?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
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
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever),
            label: const Text('WIPE DATA NOW'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isWiping = true);
      try {
        await DatabaseService.instance.wipeAllTicketSales();
        await SupabaseService.instance.wipeCloudTicketSales();
        if (!wipeSalesOnly) {
          await SupabaseService.instance.wipeCloudUnsoldTickets();
        }
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 10),
                  Text('🧹 All ticket sales & booking data wiped completely! Ready for clean testing.'),
                ],
              ),
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
                    'Testing & Data Wipe Operations (Danger Zone)',
                    style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.w700, color: Colors.redAccent),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Use these tools during testing to completely clear old ticket bookings, test sales data, and unsold tickets from both Local SQLite and Supabase Cloud DB.',
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
                          'Deletes all booked tickets from ticket_sales table in Supabase Cloud & Local DB.',
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
                    label: Text(_isWiping ? 'Wiping...' : 'Wipe Ticket Sales'),
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
                          'Wipe All Cloud Data (Sales + Unsold Tickets)',
                          style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.w600, color: Colors.redAccent),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Deletes all sales bookings as well as unsold scanner tickets from Supabase Cloud.',
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
                    label: const Text('Wipe All System Data'),
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
