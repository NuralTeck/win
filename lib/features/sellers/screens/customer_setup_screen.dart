import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../viewmodels/seller_customer_viewmodel.dart';
import '../models/seller_customer_model.dart';

class CustomerSetupScreen extends ConsumerStatefulWidget {
  const CustomerSetupScreen({super.key});

  @override
  ConsumerState<CustomerSetupScreen> createState() => _CustomerSetupScreenState();
}

class _CustomerSetupScreenState extends ConsumerState<CustomerSetupScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sellerCustomerViewModelProvider.notifier).loadSellers();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── 👑 QUICK ADD / EDIT DEALER MODAL ──────────────────────────────────────
  void _showAddEditDealerDialog([SellerCustomerModel? existing]) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final keyCtrl = TextEditingController(text: existing?.accessKey ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '123456');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final nameFocusNode = FocusNode();

    if (!isEdit) {
      nameCtrl.addListener(() {
        final clean = nameCtrl.text.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
        if (clean.isNotEmpty) {
          keyCtrl.text = '${clean}_DLR';
        }
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFF59E0B), size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              isEdit ? 'Edit Main Dealer' : '👑 Add New Main Dealer',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dealer Name *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                focusNode: nameFocusNode,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. MSM or Gupta Ji',
                  hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  prefixIcon: const Icon(Icons.business_rounded, size: 16, color: Color(0xFFF59E0B)),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Dealer User ID', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: keyCtrl,
                          style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Password', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: passCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Phone Number (Optional)', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'e.g. 9876543210',
                  hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  prefixIcon: const Icon(Icons.phone_rounded, size: 16, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final key = keyCtrl.text.trim().isEmpty ? '${name.toUpperCase()}_DLR' : keyCtrl.text.trim();
              final pass = passCtrl.text.trim().isEmpty ? '123456' : passCtrl.text.trim();

              if (isEdit) {
                ref.read(sellerCustomerViewModelProvider.notifier).updateSeller(
                      id: existing.id,
                      name: name,
                      accessKey: key,
                      password: pass,
                      phone: phoneCtrl.text.trim(),
                      isActive: existing.isActive,
                      parentDealer: null,
                      isDealer: true,
                    );
              } else {
                ref.read(sellerCustomerViewModelProvider.notifier).addSeller(
                      name: name,
                      accessKey: key,
                      password: pass,
                      phone: phoneCtrl.text.trim(),
                      isActive: true,
                      parentDealer: null,
                      isDealer: true,
                    );
              }
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: Text(isEdit ? 'Update Dealer' : 'Save Dealer', style: const TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 🌿 QUICK ADD / EDIT SUB-SELLER UNDER A DEALER ─────────────────────────
  void _showAddEditSubSellerDialog(String parentDealerName, [SellerCustomerModel? existing]) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final keyCtrl = TextEditingController(text: existing?.accessKey ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '123456');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final nameFocusNode = FocusNode();

    if (!isEdit) {
      nameCtrl.addListener(() {
        final clean = nameCtrl.text.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
        if (clean.isNotEmpty) {
          keyCtrl.text = '${clean}_${parentDealerName.replaceAll(RegExp(r'\s+'), '').toUpperCase()}';
        }
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF38BDF8), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEdit ? 'Edit Sub-Seller' : '🌿 Add Sub-Seller Branch',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Parent Dealer: $parentDealerName',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sub-Seller / Agent Name *', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                focusNode: nameFocusNode,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. Sonu, Raju, Pappu',
                  hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  prefixIcon: const Icon(Icons.person, size: 16, color: Color(0xFF38BDF8)),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Seller User ID', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: keyCtrl,
                          style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Password', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: passCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Phone Number (Optional)', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
              const SizedBox(height: 6),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'e.g. 9876543210',
                  hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  prefixIcon: const Icon(Icons.phone_rounded, size: 16, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final key = keyCtrl.text.trim().isEmpty ? '${name.toUpperCase()}_${parentDealerName.toUpperCase()}' : keyCtrl.text.trim();
              final pass = passCtrl.text.trim().isEmpty ? '123456' : passCtrl.text.trim();

              if (isEdit) {
                ref.read(sellerCustomerViewModelProvider.notifier).updateSeller(
                      id: existing.id,
                      name: name,
                      accessKey: key,
                      password: pass,
                      phone: phoneCtrl.text.trim(),
                      isActive: existing.isActive,
                      parentDealer: parentDealerName,
                      isDealer: false,
                    );
              } else {
                ref.read(sellerCustomerViewModelProvider.notifier).addSeller(
                      name: name,
                      accessKey: key,
                      password: pass,
                      phone: phoneCtrl.text.trim(),
                      isActive: true,
                      parentDealer: parentDealerName,
                      isDealer: false,
                    );
              }
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: Text(isEdit ? 'Update Seller' : 'Save Seller', style: const TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 🔁 CHANGE / ASSIGN DEALER DIALOG ──────────────────────────────────────
  void _showMoveDealerDialog(SellerCustomerModel seller, List<String> availableDealers) {
    String selectedDealer = seller.parentDealer ?? (availableDealers.isNotEmpty ? availableDealers.first : '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, color: Color(0xFF38BDF8), size: 24),
              const SizedBox(width: 10),
              Text('Link "${seller.name}" to Dealer', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Parent Dealer:', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: availableDealers.contains(selectedDealer) ? selectedDealer : (availableDealers.isNotEmpty ? availableDealers.first : null),
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E293B),
                    items: availableDealers.map((d) {
                      return DropdownMenuItem<String>(
                        value: d,
                        child: Row(
                          children: [
                            const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 8),
                            Text(d, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedDealer = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(sellerCustomerViewModelProvider.notifier).updateSeller(
                      id: seller.id,
                      name: seller.name,
                      accessKey: seller.accessKey,
                      password: seller.password,
                      phone: seller.phone,
                      isActive: seller.isActive,
                      parentDealer: selectedDealer,
                      isDealer: false,
                    );
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: Colors.black,
              ),
              child: const Text('Save Linking', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sellerCustomerViewModelProvider);
    final sellers = state.sellers;

    // Filter by search query
    final query = _searchCtrl.text.trim().toLowerCase();
    final allDealers = sellers.where((s) => s.isDealer).toList();
    final dealerNames = allDealers.map((d) => d.name).toList();

    // Map: Dealer Name -> List of Sub-Sellers
    final dealerTree = <String, List<SellerCustomerModel>>{};
    final independentSellers = <SellerCustomerModel>[];

    for (final d in allDealers) {
      dealerTree[d.name] = [];
    }

    for (final s in sellers) {
      if (s.isDealer) continue;
      if (s.parentDealer != null && s.parentDealer!.isNotEmpty && dealerTree.containsKey(s.parentDealer)) {
        dealerTree[s.parentDealer]!.add(s);
      } else {
        independentSellers.add(s);
      }
    }

    // Filter by search query
    final filteredDealers = allDealers.where((d) {
      if (query.isEmpty) return true;
      if (d.name.toLowerCase().contains(query)) return true;
      final subs = dealerTree[d.name] ?? [];
      return subs.any((sub) => sub.name.toLowerCase().contains(query));
    }).toList();

    final filteredIndependents = independentSellers.where((s) {
      if (query.isEmpty) return true;
      return s.name.toLowerCase().contains(query) || s.accessKey.toLowerCase().contains(query);
    }).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── TOP TOOLBAR & STATS ───
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withAlpha(35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_tree_rounded, size: 22, color: Color(0xFFF59E0B)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dealer & Sub-Seller Network Tree',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Interactive Hierarchy Tree • Create Main Dealers & Add Sub-Seller Branches',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
                const Spacer(),

                // Search Field
                SizedBox(
                  width: 220,
                  height: 34,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search Tree...',
                      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                      prefixIcon: const Icon(Icons.search, size: 14, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // 👑 Add Main Dealer Button
                ElevatedButton.icon(
                  onPressed: () => _showAddEditDealerDialog(),
                  icon: const Icon(Icons.add_business_rounded, size: 16),
                  label: const Text('+ Add Main Dealer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),

          // ─── TREE HIERARCHY BODY ───
          Flexible(
            child: state.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
                  )
                : (filteredDealers.isEmpty && filteredIndependents.isEmpty)
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.account_tree_outlined, size: 54, color: Colors.grey),
                              const SizedBox(height: 12),
                              const Text('No Dealers or Sellers Yet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 6),
                              const Text('Click "+ Add Main Dealer" above to build your first tree branch.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => _showAddEditDealerDialog(),
                                icon: const Icon(Icons.workspace_premium_rounded, size: 16),
                                label: const Text('Create First Dealer', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF59E0B),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(18),
                        children: [
                          // ─── 🏢 MAIN DEALER NETWORKS ───
                          ...filteredDealers.map((dealer) {
                            final subs = dealerTree[dealer.name] ?? [];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(120), width: 1.2),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 👑 Main Dealer Root Header
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF0F172A),
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                                      border: Border(bottom: BorderSide(color: Color(0xFF334155))),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF59E0B).withAlpha(40),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Icon(Icons.workspace_premium_rounded, size: 18, color: Color(0xFFF59E0B)),
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  dealer.name,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF59E0B).withAlpha(30),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: const Color(0xFFF59E0B).withAlpha(120)),
                                                  ),
                                                  child: const Text('👑 MAIN DEALER', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'ID: ${dealer.accessKey} • Phone: ${dealer.phone.isNotEmpty ? dealer.phone : "No Phone"}',
                                              style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5),
                                            ),
                                          ],
                                        ),
                                        const Spacer(),

                                        // Sub-seller count badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF38BDF8).withAlpha(30),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${subs.length} Sub-Sellers',
                                            style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // 🌿 + Add Sub-Seller Button
                                        ElevatedButton.icon(
                                          onPressed: () => _showAddEditSubSellerDialog(dealer.name),
                                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
                                          label: const Text('+ Add Sub-Seller', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0284C7),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // Edit Dealer
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
                                          tooltip: 'Edit Dealer',
                                          onPressed: () => _showAddEditDealerDialog(dealer),
                                        ),
                                        // Delete Dealer
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                          tooltip: 'Delete Dealer',
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (c) => AlertDialog(
                                                backgroundColor: const Color(0xFF1E293B),
                                                title: const Text('Delete Dealer?', style: TextStyle(color: Colors.white)),
                                                content: Text('Delete "${dealer.name}" and unlink all sub-sellers?', style: const TextStyle(color: Colors.grey)),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                    onPressed: () => Navigator.pop(c, true),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              ref.read(sellerCustomerViewModelProvider.notifier).deleteSeller(dealer.id);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),

                                  // 🌿 Sub-Seller Branches
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: subs.isEmpty
                                        ? InkWell(
                                            onTap: () => _showAddEditSubSellerDialog(dealer.name),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              decoration: BoxDecoration(
                                                border: Border.all(color: const Color(0xFF334155), style: BorderStyle.solid),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Center(
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF38BDF8)),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      'Click here to add first Sub-Seller under "${dealer.name}"',
                                                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          )
                                        : Column(
                                            children: List.generate(subs.length, (idx) {
                                              final s = subs[idx];
                                              final isLast = idx == subs.length - 1;

                                              return Container(
                                                margin: EdgeInsets.only(bottom: isLast ? 0 : 6),
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF0F172A).withAlpha(150),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: const Color(0xFF334155).withAlpha(120)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Text(
                                                      isLast ? '└── ' : '├── ',
                                                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace'),
                                                    ),
                                                    const Icon(Icons.person, size: 16, color: Colors.cyanAccent),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      s.name,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF0284C7).withAlpha(40),
                                                        borderRadius: BorderRadius.circular(3),
                                                      ),
                                                      child: Text('ID: ${s.accessKey}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                                                    ),
                                                    if (s.phone.isNotEmpty) ...[
                                                      const SizedBox(width: 8),
                                                      Text('• ${s.phone}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                                    ],
                                                    const Spacer(),

                                                    // Move Dealer
                                                    IconButton(
                                                      icon: const Icon(Icons.swap_horiz_rounded, size: 16, color: Color(0xFF38BDF8)),
                                                      tooltip: 'Move to another Dealer',
                                                      onPressed: () => _showMoveDealerDialog(s, dealerNames),
                                                    ),
                                                    // Edit
                                                    IconButton(
                                                      icon: const Icon(Icons.edit_outlined, size: 15, color: Colors.grey),
                                                      tooltip: 'Edit Sub-Seller',
                                                      onPressed: () => _showAddEditSubSellerDialog(dealer.name, s),
                                                    ),
                                                    // Delete
                                                    IconButton(
                                                      icon: const Icon(Icons.delete_outline, size: 15, color: Colors.redAccent),
                                                      tooltip: 'Delete Sub-Seller',
                                                      onPressed: () async {
                                                        final confirm = await showDialog<bool>(
                                                          context: context,
                                                          builder: (c) => AlertDialog(
                                                            backgroundColor: const Color(0xFF1E293B),
                                                            title: const Text('Delete Sub-Seller?', style: TextStyle(color: Colors.white)),
                                                            content: Text('Remove "${s.name}" from ${dealer.name}?', style: const TextStyle(color: Colors.grey)),
                                                            actions: [
                                                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                                              ElevatedButton(
                                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                                onPressed: () => Navigator.pop(c, true),
                                                                child: const Text('Delete'),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                        if (confirm == true) {
                                                          ref.read(sellerCustomerViewModelProvider.notifier).deleteSeller(s.id);
                                                        }
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ),
                                  ),
                                ],
                              ),
                            );
                          }),

                          // ─── 👤 INDEPENDENT SELLERS (NOT LINKED TO DEALER) ───
                          if (filteredIndependents.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text(
                              '👤 Direct / Independent Sellers (No Dealer Assigned)',
                              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: Column(
                                children: filteredIndependents.map((s) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12.5)),
                                        const SizedBox(width: 8),
                                        Text('ID: ${s.accessKey}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                        const Spacer(),
                                        // Promote to Dealer
                                        TextButton.icon(
                                          onPressed: () {
                                            ref.read(sellerCustomerViewModelProvider.notifier).updateSeller(
                                                  id: s.id,
                                                  name: s.name,
                                                  accessKey: s.accessKey,
                                                  password: s.password,
                                                  phone: s.phone,
                                                  isActive: s.isActive,
                                                  parentDealer: null,
                                                  isDealer: true,
                                                );
                                          },
                                          icon: const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFFF59E0B)),
                                          label: const Text('Make Main Dealer', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 6),
                                        // Link to Dealer
                                        if (dealerNames.isNotEmpty)
                                          ElevatedButton.icon(
                                            onPressed: () => _showMoveDealerDialog(s, dealerNames),
                                            icon: const Icon(Icons.link, size: 14),
                                            label: const Text('Link to Dealer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF0284C7),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
