import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../viewmodels/seller_customer_viewmodel.dart';
import '../models/seller_customer_model.dart';
import 'seller_profile_ledger_screen.dart';

class CustomerSetupScreen extends ConsumerStatefulWidget {
  const CustomerSetupScreen({super.key});

  @override
  ConsumerState<CustomerSetupScreen> createState() => _CustomerSetupScreenState();
}

class _CustomerSetupScreenState extends ConsumerState<CustomerSetupScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _visiblePasswords = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showAddEditDialog([SellerCustomerModel? existingSeller]) {
    final nameCtrl = TextEditingController(text: existingSeller?.name ?? '');
    final keyCtrl = TextEditingController(text: existingSeller?.accessKey ?? '');
    final passCtrl = TextEditingController(text: existingSeller?.password ?? '');
    final phoneCtrl = TextEditingController(text: existingSeller?.phone ?? '');

    final nameFocusNode = FocusNode();
    final keyFocusNode = FocusNode();
    final passFocusNode = FocusNode();
    final phoneFocusNode = FocusNode();

    bool isActive = existingSeller?.isActive ?? true;
    bool obscurePassword = true;

    void submitForm(BuildContext dialogCtx) {
      final name = nameCtrl.text.trim();
      final key = keyCtrl.text.trim();
      final pass = passCtrl.text.trim();
      final phone = phoneCtrl.text.trim();

      if (name.isEmpty) {
        nameFocusNode.requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter Customer / Seller Name!'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }

      if (key.isEmpty) {
        keyFocusNode.requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter Access Key / Seller ID!'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }

      if (pass.isEmpty) {
        passFocusNode.requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter Password!'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }

      if (existingSeller == null) {
        ref.read(sellerCustomerViewModelProvider.notifier).addSeller(
              name: name,
              accessKey: key,
              password: pass,
              phone: phone,
              isActive: isActive,
            );
      } else {
        ref.read(sellerCustomerViewModelProvider.notifier).updateSeller(
              id: existingSeller.id,
              name: name,
              accessKey: key,
              password: pass,
              phone: phone,
              isActive: isActive,
            );
      }

      Navigator.pop(dialogCtx);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existingSeller == null ? 'Added new Seller "$name"' : 'Updated Seller "$name"'),
          backgroundColor: AppColors.success,
        ),
      );
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                      color: AppColors.primaryContainer,
                      borderRadius: AppDecorations.radiusDefault,
                    ),
                    child: const Icon(Icons.person_add_outlined, color: AppColors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    existingSeller == null ? 'Add Customer / Seller' : 'Edit Customer / Seller',
                    style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text('Customer / Seller Name *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        focusNode: nameFocusNode,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'e.g. Rajiv Kumar',
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                          border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                        ),
                        onSubmitted: (_) => keyFocusNode.requestFocus(),
                      ),
                      const SizedBox(height: 14),

                      // Access Key
                      Text('Access Key / Seller ID *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: keyCtrl,
                        focusNode: keyFocusNode,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: 'e.g. SEL-101',
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                          border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                        ),
                        onSubmitted: (_) => passFocusNode.requestFocus(),
                      ),
                      const SizedBox(height: 14),

                      // Password
                      Text('Password *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: passCtrl,
                        focusNode: passFocusNode,
                        textInputAction: TextInputAction.next,
                        obscureText: obscurePassword,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Enter login password',
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                          border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                          ),
                        ),
                        onSubmitted: (_) => phoneFocusNode.requestFocus(),
                      ),
                      const SizedBox(height: 14),

                      // Phone Number
                      Text('Mobile Number', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: phoneCtrl,
                        focusNode: phoneFocusNode,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'e.g. 9876543210',
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                          border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                        ),
                        onSubmitted: (_) => submitForm(dialogCtx),
                      ),
                      const SizedBox(height: 16),

                      // Active Switch
                      Row(
                        children: [
                          Switch(
                            value: isActive,
                            activeThumbColor: AppColors.success,
                            onChanged: (val) => setDialogState(() => isActive = val),
                          ),
                          const SizedBox(width: 8),
                          Text('Active Status', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    nameFocusNode.dispose();
                    keyFocusNode.dispose();
                    passFocusNode.dispose();
                    phoneFocusNode.dispose();
                    if (Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () => submitForm(dialogCtx),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save Customer / Seller', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: AppColors.onPrimaryContainer,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(SellerCustomerModel seller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete seller "${seller.name}" (${seller.accessKey})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              ref.read(sellerCustomerViewModelProvider.notifier).deleteSeller(seller.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Deleted seller "${seller.name}"'), backgroundColor: AppColors.info),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sellerCustomerViewModelProvider);
    final sellers = state.filteredSellers;

    final totalCount = state.sellers.length;
    final activeCount = state.sellers.where((s) => s.isActive).length;
    final inactiveCount = totalCount - activeCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customer & Seller Master',
                    style: AppTypography.headlineLg.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage seller accounts, login credentials, access keys, and passwords',
                    style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Customer / Seller', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusDefault),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 2. Summary Badges
          Row(
            children: [
              _summaryChip('Total Accounts', '$totalCount', Icons.people_outline, AppColors.primary),
              const SizedBox(width: 16),
              _summaryChip('Active Sellers', '$activeCount', Icons.check_circle_outline, AppColors.success),
              const SizedBox(width: 16),
              _summaryChip('Inactive Sellers', '$inactiveCount', Icons.block_outlined, AppColors.warning),
            ],
          ),
          const SizedBox(height: 24),

          // 3. Search & Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: AppDecorations.radiusDefault,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search by Seller Name, Access Key, or Phone...',
                      hintStyle: TextStyle(color: AppColors.textSecondary.withAlpha(120)),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surfaceContainer,
                      border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                    ),
                    onChanged: (val) {
                      ref.read(sellerCustomerViewModelProvider.notifier).setSearchQuery(val);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Sellers Data Table
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: AppDecorations.radiusLg,
              border: Border.all(color: AppColors.border),
            ),
            child: sellers.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.person_search_outlined, size: 48, color: AppColors.textSecondary.withAlpha(100)),
                          const SizedBox(height: 12),
                          Text('No Sellers / Customers found', style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  )
                : Table(
                    columnWidths: const {
                        0: FlexColumnWidth(0.8),
                        1: FlexColumnWidth(2.2),
                        2: FlexColumnWidth(1.8),
                        3: FlexColumnWidth(2.2),
                        4: FlexColumnWidth(1.8),
                        5: FlexColumnWidth(1.4),
                        6: FlexColumnWidth(1.4),
                      },
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: AppColors.border, width: 0.8),
                      ),
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(color: AppColors.surfaceContainerHigh),
                          children: [
                            _headerCell('Sl'),
                            _headerCell('Customer / Seller Name'),
                            _headerCell('Access Key'),
                            _headerCell('Password'),
                            _headerCell('Phone'),
                            _headerCell('Status'),
                            _headerCell('Actions', alignment: Alignment.center),
                          ],
                        ),
                        ...sellers.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final s = entry.value;
                          final isPassVisible = _visiblePasswords.contains(s.id);

                          return TableRow(
                            decoration: BoxDecoration(
                              color: idx % 2 == 0 ? AppColors.surfaceContainerLow : AppColors.surfaceContainer,
                            ),
                            children: [
                              _dataCell('${idx + 1}'),
                              _dataCell(s.name, isBold: true),
                              _dataCell(s.accessKey, isMonospace: true, isBold: true, color: AppColors.primary),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        isPassVisible ? s.password : '••••••••',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontFamily: isPassVisible ? 'normal' : 'monospace',
                                          color: isPassVisible ? AppColors.tertiary : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        isPassVisible ? Icons.visibility : Icons.visibility_off,
                                        size: 16,
                                        color: AppColors.textSecondary,
                                      ),
                                      tooltip: isPassVisible ? 'Hide password' : 'Show password',
                                      onPressed: () {
                                        setState(() {
                                          if (isPassVisible) {
                                            _visiblePasswords.remove(s.id);
                                          } else {
                                            _visiblePasswords.add(s.id);
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              _dataCell(s.phone.isNotEmpty ? s.phone : '-'),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (s.isActive ? AppColors.success : AppColors.warning).withAlpha(30),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: s.isActive ? AppColors.success : AppColors.warning),
                                    ),
                                    child: Text(
                                      s.isActive ? 'ACTIVE' : 'INACTIVE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: s.isActive ? AppColors.success : AppColors.warning,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.account_balance_wallet_outlined, size: 18, color: Colors.amber),
                                      tooltip: 'View Seller Financial Ledger & Profile',
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => SellerProfileLedgerScreen(sellerName: s.name),
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                                      tooltip: 'Edit seller',
                                      onPressed: () => _showAddEditDialog(s),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                                      tooltip: 'Delete seller',
                                      onPressed: () => _confirmDelete(s),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppDecorations.radiusDefault,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
              Text(value, style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String title, {Alignment alignment = Alignment.centerLeft}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Align(
        alignment: alignment,
        child: Text(
          title,
          style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _dataCell(String text, {bool isBold = false, bool isMonospace = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontFamily: isMonospace ? 'monospace' : null,
          color: color ?? AppColors.textPrimary,
        ),
      ),
    );
  }
}
