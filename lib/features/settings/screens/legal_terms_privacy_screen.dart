import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_card.dart';

class LegalTermsPrivacyScreen extends StatefulWidget {
  final int initialTabIndex;
  const LegalTermsPrivacyScreen({super.key, this.initialTabIndex = 0});

  @override
  State<LegalTermsPrivacyScreen> createState() => _LegalTermsPrivacyScreenState();
}

class _LegalTermsPrivacyScreenState extends State<LegalTermsPrivacyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchStateCtrl = TextEditingController();
  String _searchStateQuery = '';

  static const List<Map<String, dynamic>> _stateLegalityList = [
    {
      'state': 'Nagaland',
      'status': 'LEGAL / AUTHORIZED',
      'isLegal': true,
      'details': 'Official Nagaland State Lotteries (Dear Lottery 1 PM, 6 PM, 8 PM) authorized under The Lotteries (Regulation) Act, 1998.',
    },
    {
      'state': 'West Bengal',
      'status': 'LEGAL / AUTHORIZED',
      'isLegal': true,
      'details': 'Paper lotteries fully regulated and legal under West Bengal State Directorate of Lotteries.',
    },
    {
      'state': 'Sikkim',
      'status': 'LEGAL / AUTHORIZED',
      'isLegal': true,
      'details': 'Sikkim State Lotteries authorized under Sikkim State Lotteries Rules and Central Act 39 of 1998.',
    },
    {
      'state': 'Kerala',
      'status': 'LEGAL / AUTHORIZED',
      'isLegal': true,
      'details': 'Directorate of Kerala State Lotteries (Paper lotteries only within State limits).',
    },
    {
      'state': 'Punjab',
      'status': 'LEGAL / AUTHORIZED',
      'isLegal': true,
      'details': 'Punjab State Lotteries Directorate authorized under State Lottery Rules.',
    },
    {
      'state': 'Maharashtra',
      'status': 'LEGAL / AUTHORIZED',
      'isLegal': true,
      'details': 'Maharashtra State Lotteries authorized under Finance Department of Maharashtra.',
    },
    {
      'state': 'Goa',
      'status': 'LEGAL / AUTHORIZED',
      'isLegal': true,
      'details': 'Directorate of Small Savings and Lotteries, Government of Goa.',
    },
    {
      'state': 'Mizoram',
      'status': 'LEGAL / AUTHORIZED',
      'isLegal': true,
      'details': 'Mizoram State Lotteries authorized under Institutional Finance & State Lottery Rules.',
    },
    {
      'state': 'Arunachal Pradesh',
      'status': 'LEGAL / AUTHORIZED',
      'isLegal': true,
      'details': 'Arunachal Pradesh State Lotteries authorized under Directorate of State Lotteries.',
    },
    {
      'state': 'Meghalaya',
      'status': 'LEGAL / AUTHORIZED',
      'isLegal': true,
      'details': 'Meghalaya State Lotteries regulated under State Lottery Directorate.',
    },
    {
      'state': 'Bihar',
      'status': 'STRICTLY PROHIBITED / VOID',
      'isLegal': false,
      'details': 'All paper lotteries, sales, distribution, and promotional operations are strictly banned under Bihar State Law. Operation from Bihar is strictly VOID and illegal.',
    },
    {
      'state': 'Uttar Pradesh (UP)',
      'status': 'STRICTLY PROHIBITED / VOID',
      'isLegal': false,
      'details': 'Lottery sales and distribution are banned under the Uttar Pradesh State Lotteries Prohibition Act. Operation from UP is strictly VOID.',
    },
    {
      'state': 'Gujarat',
      'status': 'STRICTLY PROHIBITED / VOID',
      'isLegal': false,
      'details': 'Lotteries prohibited under the Gujarat Prevention of Gambling Act and state notifications.',
    },
    {
      'state': 'Andhra Pradesh',
      'status': 'STRICTLY PROHIBITED / VOID',
      'isLegal': false,
      'details': 'Lotteries banned under the Andhra Pradesh Gaming Act and state regulations.',
    },
    {
      'state': 'Telangana',
      'status': 'STRICTLY PROHIBITED / VOID',
      'isLegal': false,
      'details': 'Paper lotteries banned under the Telangana Gaming Act.',
    },
    {
      'state': 'Karnataka',
      'status': 'STRICTLY PROHIBITED / VOID',
      'isLegal': false,
      'details': 'Lottery sales banned under the Karnataka Lottery Prohibition Act, 2004.',
    },
    {
      'state': 'Tamil Nadu',
      'status': 'STRICTLY PROHIBITED / VOID',
      'isLegal': false,
      'details': 'Sale and distribution of lotteries banned since 2003 under State executive orders.',
    },
    {
      'state': 'Madhya Pradesh',
      'status': 'STRICTLY PROHIBITED / VOID',
      'isLegal': false,
      'details': 'Paper lotteries banned under the Madhya Pradesh Lottery Pratibandh Adhiniyam.',
    },
    {
      'state': 'Rajasthan',
      'status': 'STRICTLY PROHIBITED / VOID',
      'isLegal': false,
      'details': 'Lotteries banned under Rajasthan Public Gambling and state lottery prohibitory orders.',
    },
    {
      'state': 'Odisha',
      'status': 'STRICTLY PROHIBITED / VOID',
      'isLegal': false,
      'details': 'Lottery sales and trading prohibited under Odisha State Government notifications.',
    },
    {
      'state': 'Delhi (NCT)',
      'status': 'PROHIBITED RETAIL SALES',
      'isLegal': false,
      'details': 'Retail paper lottery sale points within Delhi NCT territory are prohibited by Government of NCT of Delhi.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchStateCtrl.dispose();
    super.dispose();
  }

  void _copyToClipboard(String title, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📋 $title copied to clipboard!', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withAlpha(30),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF38BDF8).withAlpha(100)),
              ),
              child: const Icon(Icons.gavel_rounded, color: Color(0xFF38BDF8), size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LEGAL, TERMS & PRIVACY POLICY',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5, color: Colors.white),
                ),
                Text(
                  'Statutory Compliance · The Lotteries (Regulation) Act, 1998 · Offline ERP',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Copy Terms & Statutory Disclaimer',
            icon: const Icon(Icons.copy_rounded, color: Color(0xFF38BDF8), size: 20),
            onPressed: () => _copyToClipboard(
              'Terms & Statutory Disclaimer',
              'STATUTORY COMPLIANCE NOTICE:\n\n'
              '1. Valid ONLY in authorized Indian States (Nagaland, West Bengal, Sikkim, Kerala, Punjab, Maharashtra, Goa, Mizoram, Arunachal Pradesh, Meghalaya) under The Lotteries (Regulation) Act, 1998.\n'
              '2. STRICTLY VOID AND PROHIBITED in banned states (Bihar, UP, Gujarat, Andhra Pradesh, Telangana, Karnataka, Tamil Nadu, MP, Rajasthan, Odisha etc.).\n'
              '3. This software is purely an internal B2B stock inventory and ledger hisab ERP. It does not conduct online lotteries, does not sell tickets online, and does not accept bets.\n'
              '4. All cash (nagad) and commercial ledger balances are offline B2B accounts governed by authorized distributor agreements.\n'
              '5. 100% Offline-First: All data is saved strictly in local SQLite database on your device with zero cloud tracking.',
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF38BDF8),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
          tabs: const [
            Tab(icon: Icon(Icons.description_outlined, size: 18), text: 'Terms of Service & Disclaimer'),
            Tab(icon: Icon(Icons.shield_outlined, size: 18), text: 'Privacy Policy (Offline-First)'),
            Tab(icon: Icon(Icons.map_outlined, size: 18), text: 'State-Wise Legality & Void Directory'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTermsOfServiceTab(),
          _buildPrivacyPolicyTab(),
          _buildStateLegalityTab(),
        ],
      ),
    );
  }

  // ─── TAB 1: TERMS OF SERVICE ───────────────────────────────────────────────
  Widget _buildTermsOfServiceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Alert (Void Where Prohibited)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF7F1D1D).withAlpha(140), const Color(0xFF1E1B4B).withAlpha(140)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withAlpha(180), width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'CRITICAL STATUTORY RESTRICTION: VOID WHERE PROHIBITED',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Yeh software sirf aur sirf un Bharatiya rajyon (States) ke liye valid hai jahan The Lotteries (Regulation) Act, 1998 ke tahet Government Paper Lotteries (jaise Nagaland State Dear Lotteries) legally permitted hain. Kisi bhi prohibited state (jaise Bihar, UP, Gujarat, Andhra, Telangana, Karnataka etc.) me iska upyog poori tarah se AVAI DH (VOID/ILLEGAL) hai.',
                        style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 1
          _buildLegalCard(
            title: '1. APPLICABILITY & AUTHORIZED JURISDICTIONS (वैधता एवं अधिकार क्षेत्र)',
            icon: Icons.check_circle_outline,
            iconColor: Colors.greenAccent,
            children: [
              _buildParagraph(
                'This Software ("PhantomManagement / OpsCore Pro") is strictly designed for licensed stockists, distributors, and dealers operating in jurisdictions where state-run paper lotteries are fully authorized by law under The Lotteries (Regulation) Act, 1998 (Central Act 39 of 1998).',
              ),
              const SizedBox(height: 10),
              _buildBullet(
                'Authorized States (वैध राज्य):',
                'Nagaland (including official Nagaland State Dear Lotteries 1 PM, 6 PM, 8 PM), West Bengal, Sikkim, Kerala, Punjab, Maharashtra, Goa, Mizoram, Arunachal Pradesh, and Meghalaya.',
                Colors.greenAccent,
              ),
              const SizedBox(height: 6),
              _buildBullet(
                'Strictly Void Territories (प्रतिबंधित क्षेत्र):',
                'The software is strictly VOID in Bihar, Uttar Pradesh, Gujarat, Andhra Pradesh, Telangana, Karnataka, Tamil Nadu, Madhya Pradesh, Rajasthan, Odisha, Delhi NCT (retail), and any jurisdiction where lotteries are banned under state statutes.',
                Colors.redAccent,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Section 2
          _buildLegalCard(
            title: '2. NATURE OF THE SOFTWARE (B2B ACCOUNTING ERP ONLY)',
            icon: Icons.inventory_2_outlined,
            iconColor: Colors.amberAccent,
            children: [
              _buildBullet(
                'Purely an ERP Tool:',
                'This application is an internal inventory stock management, voucher issuance, unsold return reconciliation, and accounting ledger system for authorized distributors.',
                Colors.amberAccent,
              ),
              _buildBullet(
                'NO Online Gambling:',
                'The Software does NOT conduct lotteries, does NOT accept online bets, does NOT sell tickets to the general public online, and does NOT hold customer prize money.',
                Colors.white70,
              ),
              _buildBullet(
                'No Custody of Funds:',
                'The Software does not operate digital wallets or payment gateways. All financial settlements occur independently between commercial entities.',
                Colors.white70,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Section 3
          _buildLegalCard(
            title: '3. COMMERCIAL CASH (NAGAD) & SETTLEMENTS (नकद लेन-देन एवं बहीखाता)',
            icon: Icons.currency_rupee,
            iconColor: Colors.cyanAccent,
            children: [
              _buildParagraph(
                'All calculations, voucher stock debits, unsold return credits, and final net billable amounts computed by the system represent commercial accounting records between distributors, main dealers, and sub-sellers.',
              ),
              const SizedBox(height: 8),
              _buildBullet(
                'Nagad & Offline Transactions:',
                'Any cash transactions ("nagad"), bank transfers, or payments exchanged between parties are private commercial dealings between independent businesses. The Software acts strictly as a digital accounting ledger.',
                Colors.cyanAccent,
              ),
              _buildBullet(
                'Data Accuracy Responsibility:',
                'The Licensee/User is solely responsible for verifying the accuracy of ticket ranges, quantities, purchase rates, and returned unsold stock before confirming accounts.',
                Colors.white70,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Section 4
          _buildLegalCard(
            title: '4. RESULT VERIFICATION & INAM TAX COMPLIANCE (परिणाम एवं टीडीएस)',
            icon: Icons.emoji_events_outlined,
            iconColor: const Color(0xFFF59E0B),
            children: [
              _buildBullet(
                'Gazette Reference Precedence:',
                'Draw results entered (Sambad / Dear 1 PM, 6 PM, 8 PM) are for reference reconciliation. In case of any dispute, the Official State Government Gazette published by the respective State Lottery Department shall be final and binding.',
                Colors.amberAccent,
              ),
              _buildBullet(
                'Unsold Anti-Fraud Rule:',
                'Any ticket returned in Unsold stock prior to the draw belongs to the issuing agency and is strictly excluded from dealer prize claims.',
                Colors.white70,
              ),
              _buildBullet(
                'Income Tax TDS (Section 194B):',
                'All paying distributors are solely responsible for compliance with Section 194B of the Indian Income Tax Act, 1961 (TDS deduction on lottery prize winnings exceeding ₹10,000) and applicable GST norms.',
                Colors.white70,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Section 5
          _buildLegalCard(
            title: '5. LIMITATION OF LIABILITY & INDEMNIFICATION (दायित्व की सीमा)',
            icon: Icons.shield_outlined,
            iconColor: Colors.purpleAccent,
            children: [
              _buildParagraph(
                'The Software is licensed on an "AS IS" and "AS AVAILABLE" basis without warranties of any kind. The software developers, publishers, and distributors shall not be liable for any indirect, incidental, punitive, or consequential damages resulting from the use, operation, or misuse of this software.',
              ),
              const SizedBox(height: 8),
              _buildParagraph(
                'The Licensee agrees to indemnify, defend, and hold harmless the software authors from any legal claims, administrative penalties, or losses resulting from the Licensee\'s failure to adhere to statutory lottery regulations or deployment in unauthorized territories.',
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── TAB 2: PRIVACY POLICY ────────────────────────────────────────────────
  Widget _buildPrivacyPolicyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF064E3B).withAlpha(120),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981).withAlpha(180), width: 1.5),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_rounded, color: Color(0xFF10B981), size: 28),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '100% OFFLINE-FIRST ARCHITECTURE (पूर्णतः स्थानीय डेटा सुरक्षा)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Aapka sara hisab, dealer list, ticket vouchers aur financial balances aapke apne computer par SQLite database me store hote hain. Hamare paas aapka koi data transmit ya upload nahi hota.',
                        style: TextStyle(color: Color(0xFFA7F3D0), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildLegalCard(
            title: '1. LOCAL DATA STORAGE (स्थानीय डेटा भंडारण)',
            icon: Icons.storage_rounded,
            iconColor: const Color(0xFF38BDF8),
            children: [
              _buildBullet(
                'Local SQLite Database:',
                'All records—including vouchers, unsold returns, dealer directories, and billable settlements—are stored strictly on your local PC in opscore_pro.db.',
                const Color(0xFF38BDF8),
              ),
              _buildBullet(
                'Zero Cloud Harvesting:',
                'We do NOT maintain central servers to harvest, collect, or monetize your business ledgers, customer phone numbers, or ticket details.',
                Colors.white70,
              ),
              _buildBullet(
                '100% Data Ownership:',
                'You own 100% of your business data. You can backup, export to CSV, or wipe your database at any time.',
                Colors.white70,
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildLegalCard(
            title: '2. SCANNING & IMAGE PROCESSING PRIVACY (फोटो एवं स्कैनर गोपनीयता)',
            icon: Icons.document_scanner_outlined,
            iconColor: Colors.amberAccent,
            children: [
              _buildParagraph(
                'When you use the AI Camera / Photo Scanner for Parcha or Voucher review:',
              ),
              const SizedBox(height: 6),
              _buildBullet(
                'Ephemeral Processing:',
                'Scanned images are read locally or transmitted ephemerally via secure SSL/HTTPS solely for text character recognition (OCR).',
                Colors.amberAccent,
              ),
              _buildBullet(
                'No Persistent Cloud Storage:',
                'Images are not permanently stored, indexed, or shared with third-party advertisers.',
                Colors.white70,
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildLegalCard(
            title: '3. ACCESS CONTROLS & SECURITY BEST PRACTICES',
            icon: Icons.admin_panel_settings_outlined,
            iconColor: Colors.purpleAccent,
            children: [
              _buildBullet(
                'Role-Based PIN Security:',
                'The Software supports Administrative Security PINs to lock sensitive screens (Pricing, Ledger Reset, Dealer Hisab).',
                Colors.purpleAccent,
              ),
              _buildBullet(
                'Host Machine Responsibility:',
                'Because the database resides locally, users should maintain standard operating system password protection and antivirus measures on the host computer.',
                Colors.white70,
              ),
              _buildBullet(
                'Master Data Wipe (0):',
                'Administrators have full capability to purge operational tables back to zero at will using the Master System Reset feature.',
                Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── TAB 3: STATE LEGALITY DIRECTORY ──────────────────────────────────────
  Widget _buildStateLegalityTab() {
    final filtered = _searchStateQuery.isEmpty
        ? _stateLegalityList
        : _stateLegalityList.where((s) => s['state'].toString().toLowerCase().contains(_searchStateQuery.toLowerCase())).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'STATE-WISE LOTTERY LEGALITY DIRECTORY',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The Lotteries (Regulation) Act, 1998 (Act 39 of 1998) State-wise Status',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 280,
                height: 38,
                child: TextField(
                  controller: _searchStateCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search State (e.g. Nagaland, Bihar)...',
                    hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF38BDF8)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                  ),
                  onChanged: (val) => setState(() => _searchStateQuery = val.trim()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final item = filtered[i];
                final isLegal = item['isLegal'] as bool;
                final statusColor = isLegal ? Colors.greenAccent : Colors.redAccent;
                final bgColor = isLegal ? const Color(0xFF064E3B).withAlpha(50) : const Color(0xFF7F1D1D).withAlpha(50);
                final borderColor = isLegal ? const Color(0xFF059669).withAlpha(120) : const Color(0xFFDC2626).withAlpha(120);

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor, width: 1.2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isLegal ? Icons.check_circle_rounded : Icons.block_flipped,
                          color: statusColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  item['state'],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withAlpha(40),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: statusColor),
                                  ),
                                  child: Text(
                                    item['status'],
                                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item['details'],
                              style: TextStyle(color: Colors.grey.shade300, fontSize: 12, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPER WIDGETS ────────────────────────────────────────────────────────
  Widget _buildLegalCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: Colors.white),
              ),
            ],
          ),
          const Divider(height: 20, color: Color(0xFF334155)),
          ...children,
        ],
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Text(
      text,
      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5, height: 1.45),
    );
  }

  Widget _buildBullet(String boldPrefix, String text, Color prefixColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: prefixColor, fontWeight: FontWeight.bold, fontSize: 14)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5, height: 1.4),
                children: [
                  TextSpan(text: '$boldPrefix ', style: TextStyle(fontWeight: FontWeight.bold, color: prefixColor)),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
