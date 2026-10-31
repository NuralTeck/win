import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/database/database_service.dart';
import '../models/collector_model.dart';

class CollectorManagementScreen extends ConsumerStatefulWidget {
  const CollectorManagementScreen({super.key});

  @override
  ConsumerState<CollectorManagementScreen> createState() => _CollectorManagementScreenState();
}

class _CollectorManagementScreenState extends ConsumerState<CollectorManagementScreen> {
  List<CollectorModel> _collectors = [];
  List<CollectorPaymentModel> _payments = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterMode = 'All'; // 'All', 'Cash', 'Online'
  final String _selectedCollectorFilter = 'All';
  DateTime _selectedDate = DateTime.now();
  bool _filterByDate = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Load Collectors from local SQLite only
    final localCollectors = await DatabaseService.instance.getCollectors();

    final Map<String, CollectorModel> collectorMap = {};

    // Seed demo collector if empty
    if (localCollectors.isEmpty) {
      final demo = CollectorModel(
        id: 'col_101',
        accessKey: 'COL-101',
        name: 'Rahul Sharma (Money Collector)',
        phone: '9876543210',
        password: '123',
        isActive: true,
        createdAt: DateTime.now(),
      );
      collectorMap[demo.id] = demo;
      await DatabaseService.instance.insertCollector(demo.toMap());
    }

    for (final c in localCollectors) {
      final model = CollectorModel.fromMap(c);
      collectorMap[model.id] = model;
    }

    // Load Collector Payments from local SQLite only
    final localPayments = await DatabaseService.instance.getCollectorPayments();

    final Map<String, CollectorPaymentModel> paymentMap = {};
    for (final p in localPayments) {
      final model = CollectorPaymentModel.fromMap(p);
      paymentMap[model.id] = model;
    }

    if (mounted) {
      setState(() {
        _collectors = collectorMap.values.toList();
        _payments = paymentMap.values.toList()..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
        _isLoading = false;
      });
    }
  }

  void _showAddCollectorDialog({String? defaultKey, String? defaultPass}) {
    final rand = Random();
    final autoKey = defaultKey ?? 'COL-${rand.nextInt(8999) + 1000}';
    final autoPass = defaultPass ?? 'PASS-${rand.nextInt(8999) + 1000}';

    final keyCtrl = TextEditingController(text: autoKey);
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController(text: autoPass);

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text('Register New Money Collector', style: AppTypography.titleLg),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final newKey = 'COL-${rand.nextInt(8999) + 1000}';
                  final newPass = 'PASS-${rand.nextInt(8999) + 1000}';
                  keyCtrl.text = newKey;
                  passCtrl.text = newPass;
                  setDialogState(() {});
                },
                icon: const Icon(Icons.key, size: 16, color: Colors.amberAccent),
                label: const Text('GENERATE NEW KEY', style: TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amberAccent)),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withAlpha(25),
                    borderRadius: AppDecorations.radiusDefault,
                    border: Border.all(color: Colors.amberAccent.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.vpn_key, color: Colors.amberAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Key is used by Money Collector to log into the mobile app.',
                          style: AppTypography.bodySm.copyWith(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: keyCtrl,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent),
                  decoration: const InputDecoration(labelText: 'Collector Access Key / ID *', prefixIcon: Icon(Icons.badge, color: Colors.amberAccent)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Collector Full Name *', prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(labelText: 'Login Password *', prefixIcon: Icon(Icons.lock)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: () async {
                if (keyCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill Access Key and Collector Name!'), backgroundColor: AppColors.error),
                  );
                  return;
                }

                final newCollector = CollectorModel(
                  id: 'col_${DateTime.now().millisecondsSinceEpoch}',
                  accessKey: keyCtrl.text.trim().toUpperCase(),
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  password: passCtrl.text.trim(),
                  isActive: true,
                  createdAt: DateTime.now(),
                );

                await DatabaseService.instance.insertCollector(newCollector.toMap());

                if (dialogCtx.mounted && Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
                _loadData();
                _showSnackbar('🔑 Registered Collector Key ${newCollector.accessKey} for ${newCollector.name}!', AppColors.success);
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Save & Issue Key'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditCollectorDialog(CollectorModel collector) {
    final rand = Random();
    final keyCtrl = TextEditingController(text: collector.accessKey);
    final nameCtrl = TextEditingController(text: collector.name);
    final phoneCtrl = TextEditingController(text: collector.phone);
    final passCtrl = TextEditingController(text: collector.password);
    bool isActive = collector.isActive;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusLg),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit, color: AppColors.secondary),
                  const SizedBox(width: 10),
                  Text('Edit Collector Profile & Credentials', style: AppTypography.titleLg),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () {
                  keyCtrl.text = 'COL-${rand.nextInt(8999) + 1000}';
                  passCtrl.text = 'PASS-${rand.nextInt(8999) + 1000}';
                  setDialogState(() {});
                },
                icon: const Icon(Icons.key, size: 16, color: Colors.amberAccent),
                label: const Text('REGENERATE KEY', style: TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amberAccent)),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: keyCtrl,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent),
                  decoration: const InputDecoration(labelText: 'Collector Access Key / ID *', prefixIcon: Icon(Icons.badge, color: Colors.amberAccent)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Collector Full Name *', prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(labelText: 'Login Password *', prefixIcon: Icon(Icons.lock)),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Account Active Status', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(isActive ? 'Collector can log in' : 'Collector login disabled'),
                  value: isActive,
                  onChanged: (val) => setDialogState(() => isActive = val),
                  activeThumbColor: Colors.greenAccent,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: () async {
                if (keyCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill Access Key and Name!'), backgroundColor: AppColors.error),
                  );
                  return;
                }

                final updatedCollector = CollectorModel(
                  id: collector.id,
                  accessKey: keyCtrl.text.trim().toUpperCase(),
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  password: passCtrl.text.trim(),
                  isActive: isActive,
                  createdAt: collector.createdAt,
                );

                await DatabaseService.instance.insertCollector(updatedCollector.toMap());

                if (dialogCtx.mounted && Navigator.canPop(dialogCtx)) Navigator.pop(dialogCtx);
                _loadData();
                _showSnackbar('✏️ Updated Credentials for ${updatedCollector.name} (Key: ${updatedCollector.accessKey})', AppColors.success);
              },
              icon: const Icon(Icons.save),
              label: const Text('UPDATE CREDENTIALS'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportToCsv(List<CollectorPaymentModel> list) async {
    if (list.isEmpty) {
      _showSnackbar('No collection records to export!', AppColors.warning);
      return;
    }

    try {
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Collector Payments Ledger',
        fileName: 'collector_payments_$dateStr.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (filePath == null) return;

      final buffer = StringBuffer();
      buffer.writeln('SL,Collector ID,Collector Name,Seller Name,Amount (Rs),Payment Mode,Ref/UTR No,Remark,Collection Date');

      for (int i = 0; i < list.length; i++) {
        final p = list[i];
        buffer.writeln('${i + 1},"${p.collectorId}","${p.collectorName}","${p.sellerName}",${p.amount},"${p.paymentMode}","${p.refNumber}","${p.remark}","${DateFormat('yyyy-MM-dd HH:mm').format(p.collectedAt)}"');
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      _showSnackbar('📊 Exported ${list.length} Collection Ledger records to $filePath', AppColors.success);
    } catch (e) {
      _showSnackbar('Export error: $e', AppColors.error);
    }
  }

  void _showSnackbar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(60),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final filteredPayments = _payments.where((p) {
      if (_filterByDate) {
        final pDateStr = DateFormat('yyyy-MM-dd').format(p.collectedAt);
        final selDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
        if (pDateStr != selDateStr) return false;
      }
      if (_filterMode != 'All' && p.paymentMode.toLowerCase() != _filterMode.toLowerCase()) {
        return false;
      }
      if (_selectedCollectorFilter != 'All' && p.collectorName != _selectedCollectorFilter && p.collectorId != _selectedCollectorFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchSeller = p.sellerName.toLowerCase().contains(q);
        final matchCollector = p.collectorName.toLowerCase().contains(q);
        final matchRef = p.refNumber.toLowerCase().contains(q);
        if (!matchSeller && !matchCollector && !matchRef) return false;
      }
      return true;
    }).toList();

    double totalCash = 0.0;
    double totalOnline = 0.0;
    final Set<String> uniqueSellers = {};

    for (final p in filteredPayments) {
      if (p.paymentMode.toLowerCase() == 'cash') {
        totalCash += p.amount;
      } else {
        totalOnline += p.amount;
      }
      if (p.sellerName.isNotEmpty) uniqueSellers.add(p.sellerName);
    }

    final totalCollected = totalCash + totalOnline;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(30),
                      borderRadius: AppDecorations.radiusLg,
                      border: Border.all(color: AppColors.primary.withAlpha(80)),
                    ),
                    child: const Icon(Icons.payments, color: Colors.greenAccent, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MONEY COLLECTOR MANAGEMENT & SELLER PAYMENTS',
                        style: AppTypography.headlineLg.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Real-time cash & online payment collections from sellers by money collectors',
                        style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _showAddCollectorDialog,
                    icon: const Icon(Icons.person_add, color: Colors.white, size: 18),
                    label: const Text('+ ADD COLLECTOR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh, color: Colors.greenAccent, size: 18),
                    label: const Text('REFRESH CLOUD', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.greenAccent), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _exportToCsv(filteredPayments),
                    icon: const Icon(Icons.description, color: Colors.white, size: 18),
                    label: const Text('EXPORT LEDGER (.CSV)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Day-by-Day Date Selector & Active Date Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: AppDecorations.radiusDefault,
              border: Border.all(color: AppColors.primary.withAlpha(80)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.amberAccent, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      _filterByDate
                          ? 'DAY-BY-DAY COLLECTION FOR: ${DateFormat('dd/MM/yyyy (EEEE)').format(_selectedDate)}'
                          : 'SHOWING ALL DATES COLLECTION LEDGER HISTORY',
                      style: AppTypography.titleMd.copyWith(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: () => setState(() {
                        _selectedDate = DateTime.now();
                        _filterByDate = true;
                      }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (_filterByDate && DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now()))
                            ? AppColors.primary
                            : AppColors.surfaceContainerHigh,
                      ),
                      child: const Text('Today'),
                    ),
                    ElevatedButton(
                      onPressed: () => setState(() {
                        _selectedDate = DateTime.now().subtract(const Duration(days: 1));
                        _filterByDate = true;
                      }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (_filterByDate && DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1))))
                            ? AppColors.primary
                            : AppColors.surfaceContainerHigh,
                      ),
                      child: const Text('Yesterday'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final first = _selectedDate.isBefore(DateTime(2020)) ? _selectedDate : DateTime(2020);
                        final last = _selectedDate.isAfter(DateTime(2035)) ? _selectedDate : DateTime(2035);
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: first,
                          lastDate: last,
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedDate = picked;
                            _filterByDate = true;
                          });
                        }
                      },
                      icon: const Icon(Icons.edit_calendar, size: 16, color: AppColors.secondary),
                      label: const Text('Pick Date', style: TextStyle(color: AppColors.secondary)),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _filterByDate = false),
                      child: Text(
                        'All Dates',
                        style: TextStyle(color: !_filterByDate ? AppColors.secondary : AppColors.textSecondary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // KPI Cards
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'TOTAL COLLECTED',
                  value: '₹${NumberFormat('#,##,##0', 'en_IN').format(totalCollected)}',
                  subtitle: '${filteredPayments.length} Payment Entries',
                  icon: Icons.account_balance_wallet,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'TOTAL CASH COLLECTED',
                  value: '₹${NumberFormat('#,##,##0', 'en_IN').format(totalCash)}',
                  subtitle: 'Physical Cash Payments',
                  icon: Icons.money,
                  color: Colors.amberAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'TOTAL ONLINE / UPI',
                  value: '₹${NumberFormat('#,##,##0', 'en_IN').format(totalOnline)}',
                  subtitle: 'Digital UPI Transfer Payments',
                  icon: Icons.qr_code_2,
                  color: Colors.lightBlueAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'ACTIVE COLLECTORS',
                  value: '${_collectors.where((c) => c.isActive).length} Collectors',
                  subtitle: '${uniqueSellers.length} Sellers Collected From',
                  icon: Icons.badge,
                  color: Colors.purpleAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Registered Money Collectors Grid / Bar
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      Text('REGISTERED MONEY COLLECTORS DIRECTORY', style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold)),
                      Text('${_collectors.length} Registered Collectors', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _collectors.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: Text('No collectors registered yet. Click "+ ADD COLLECTOR" to add.', style: TextStyle(color: AppColors.textSecondary))),
                        )
                      : Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: _collectors.map((c) {
                            final collectorPayments = _payments.where((p) => p.collectorId == c.id || p.collectorName == c.name).toList();
                            final cCash = collectorPayments.where((p) => p.paymentMode.toLowerCase() == 'cash').fold(0.0, (sum, p) => sum + p.amount);
                            final cOnline = collectorPayments.where((p) => p.paymentMode.toLowerCase() == 'online').fold(0.0, (sum, p) => sum + p.amount);

                            return Container(
                              width: 320,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: AppDecorations.radiusDefault,
                                border: Border.all(color: c.isActive ? AppColors.primary.withAlpha(100) : AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: AppColors.primary.withAlpha(40),
                                        child: Text(c.name.substring(0, 1).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(c.name, style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                            Text('Key: ${c.accessKey} | ${c.phone}', style: AppTypography.bodySm),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: AppColors.secondary, size: 20),
                                        tooltip: 'Edit Access Key & Password',
                                        onPressed: () => _showEditCollectorDialog(c),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Cash Collected', style: TextStyle(fontSize: 10, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                                          Text('₹${cCash.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Online Collected', style: TextStyle(fontSize: 10, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
                                          Text('₹${cOnline.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Total Collected', style: TextStyle(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                          Text('₹${(cCash + cOnline).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.greenAccent)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Master Seller Collection Ledger Table
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      Text('MASTER SELLER PAYMENTS COLLECTION LEDGER', style: AppTypography.titleLg.copyWith(fontWeight: FontWeight.bold)),
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Search Box
                          SizedBox(
                            width: 220,
                            height: 38,
                            child: TextField(
                              onChanged: (val) => setState(() => _searchQuery = val),
                              decoration: InputDecoration(
                                hintText: 'Search seller/collector/ref...',
                                prefixIcon: const Icon(Icons.search, size: 16),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                                border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault),
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),

                          // Mode Segment
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'All', label: Text('All Mode', style: TextStyle(fontSize: 12))),
                              ButtonSegment(value: 'Cash', label: Text('Cash', style: TextStyle(fontSize: 12))),
                              ButtonSegment(value: 'Online', label: Text('Online', style: TextStyle(fontSize: 12))),
                            ],
                            selected: {_filterMode},
                            onSelectionChanged: (val) => setState(() => _filterMode = val.first),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  filteredPayments.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(
                            child: Text(
                              'No seller payment collection records found.',
                              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: AppDecorations.radiusDefault,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerHigh,
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                                  border: Border(bottom: BorderSide(color: AppColors.border)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(flex: 1, child: Text('SL', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 3, child: Text('COLLECTOR', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 3, child: Text('SELLER NAME', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 3, child: Text('AMOUNT (₹)', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 2, child: Text('PAYMENT MODE', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 3, child: Text('REF / UTR NO', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 3, child: Text('REMARK', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 3, child: Text('COLLECTION TIME', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold))),
                                  ],
                                ),
                              ),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filteredPayments.length,
                                separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                                itemBuilder: (context, idx) {
                                  final p = filteredPayments[idx];
                                  final isCash = p.paymentMode.toLowerCase() == 'cash';

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    color: idx % 2 == 0 ? AppColors.surfaceContainerLow : AppColors.surfaceContainerHigh.withAlpha(40),
                                    child: Row(
                                      children: [
                                        Expanded(flex: 1, child: Text('${idx + 1}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                                        Expanded(flex: 3, child: Text(p.collectorName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                        Expanded(flex: 3, child: Text(p.sellerName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent))),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            '₹${NumberFormat('#,##,##0.00', 'en_IN').format(p.amount)}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 15),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: (isCash ? Colors.amber : Colors.lightBlue).withAlpha(30),
                                              borderRadius: AppDecorations.radiusSm,
                                              border: Border.all(color: isCash ? Colors.amber : Colors.lightBlue),
                                            ),
                                            child: Text(
                                              p.paymentMode.toUpperCase(),
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isCash ? Colors.amberAccent : Colors.lightBlueAccent),
                                            ),
                                          ),
                                        ),
                                        Expanded(flex: 3, child: Text(p.refNumber, style: const TextStyle(fontSize: 13))),
                                        Expanded(flex: 3, child: Text(p.remark.isNotEmpty ? p.remark : '-', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                                        Expanded(flex: 3, child: Text(DateFormat('dd/MM/yyyy HH:mm').format(p.collectedAt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            Text(value, style: AppTypography.headlineLg.copyWith(color: color, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
