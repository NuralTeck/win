import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/utils/formatters.dart';
import '../viewmodels/agents_viewmodel.dart';
import '../../shared/models/agent_model.dart';

class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentsViewModelProvider);
    final notifier = ref.read(agentsViewModelProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ticket Agents & Distributors',
                      style: AppTypography.headlineLg.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Licensed agents, master distributors, retail outlets and stockists',
                      style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  AppSecondaryButton(
                    label: 'Export List',
                    icon: Icons.download_outlined,
                    onPressed: () {},
                  ),
                  const SizedBox(width: 12),
                  AppPrimaryButton(
                    label: 'Add New Agent',
                    icon: Icons.person_add_outlined,
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Summary Bar ───────────────────────────────────────────────────
          Row(
            children: [
              _AgentSummaryChip(
                label: 'Total Agents',
                value: state.agents.length.toString(),
                color: AppColors.primary,
                icon: Icons.badge_outlined,
              ),
              const SizedBox(width: 12),
              _AgentSummaryChip(
                label: 'Active',
                value: state.agents.where((a) => a.status == AgentStatus.active).length.toString(),
                color: AppColors.success,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 12),
              _AgentSummaryChip(
                label: 'Under Review',
                value: state.agents.where((a) => a.status == AgentStatus.underReview).length.toString(),
                color: AppColors.warning,
                icon: Icons.schedule,
              ),
              const SizedBox(width: 12),
              _AgentSummaryChip(
                label: 'Total Monthly Sales',
                value: Formatters.formatIndianCurrency(
                  state.agents.fold(0.0, (sum, a) => sum + a.monthlySales),
                ),
                color: AppColors.tertiary,
                icon: Icons.currency_rupee,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Search & License Filters ──────────────────────────────────────
          Row(
            children: [
              SizedBox(
                width: 340,
                child: AppSearchField(
                  hintText: 'Search agent name, code, district...',
                  onChanged: notifier.setSearchQuery,
                ),
              ),
              const SizedBox(width: 16),
              _LicenseChip(
                label: 'All',
                isSelected: state.selectedLicense == null,
                onTap: () => notifier.setLicenseFilter(null),
              ),
              const SizedBox(width: 8),
              _LicenseChip(
                label: 'Master',
                isSelected: state.selectedLicense == AgentLicense.master,
                onTap: () => notifier.setLicenseFilter(AgentLicense.master),
              ),
              const SizedBox(width: 8),
              _LicenseChip(
                label: 'District',
                isSelected: state.selectedLicense == AgentLicense.district,
                onTap: () => notifier.setLicenseFilter(AgentLicense.district),
              ),
              const SizedBox(width: 8),
              _LicenseChip(
                label: 'Retail',
                isSelected: state.selectedLicense == AgentLicense.retail,
                onTap: () => notifier.setLicenseFilter(AgentLicense.retail),
              ),
              const SizedBox(width: 8),
              _LicenseChip(
                label: 'Stockist',
                isSelected: state.selectedLicense == AgentLicense.stockist,
                onTap: () => notifier.setLicenseFilter(AgentLicense.stockist),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Agents Table ──────────────────────────────────────────────────
          AppDataTable(
            isLoading: state.isLoading,
            columns: const [
              AppTableColumn(label: 'AGENT CODE', width: 110),
              AppTableColumn(label: 'AGENT NAME & OWNER'),
              AppTableColumn(label: 'DISTRICT', width: 110),
              AppTableColumn(label: 'LICENSE', width: 110),
              AppTableColumn(label: 'MONTHLY SALES', width: 140),
              AppTableColumn(label: 'TICKETS SOLD', width: 120),
              AppTableColumn(label: 'COMMISSION', width: 120),
              AppTableColumn(label: 'RATING', width: 80),
              AppTableColumn(label: 'STATUS', width: 110),
              AppTableColumn(label: 'ACTIONS', width: 60, alignment: Alignment.centerRight),
            ],
            rows: state.filteredAgents.map((a) {
              return [
                Text(
                  a.agentCode,
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      a.agentName,
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Owner: ${a.ownerName}',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.textSecondary.withAlpha(150),
                      ),
                    ),
                  ],
                ),
                Text(
                  a.district,
                  style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                ),
                StatusBadge.fromStatus(a.license.name),
                Text(
                  Formatters.formatIndianCurrency(a.monthlySales),
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  Formatters.formatNumber(a.ticketsSold),
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Formatters.formatIndianCurrency(a.commissionEarned),
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.tertiary,
                      ),
                    ),
                    Text(
                      '${a.commissionRate}% rate',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.textSecondary.withAlpha(150),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.star, size: 14, color: AppColors.tertiary),
                    const SizedBox(width: 4),
                    Text(
                      a.rating.toStringAsFixed(1),
                      style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                StatusBadge.fromStatus(a.status.name),
                IconButton(
                  icon: const Icon(Icons.tune, size: 18, color: AppColors.primary),
                  tooltip: 'Edit Agent Profile',
                  onPressed: () {},
                ),
              ];
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _AgentSummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _AgentSummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: AppDecorations.radiusDefault,
        border: Border.all(color: color.withAlpha(60), width: 1),
      ),
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
              Text(
                value,
                style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LicenseChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _LicenseChip({required this.label, required this.isSelected, required this.onTap});

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
