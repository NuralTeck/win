import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_decorations.dart';
import '../../../core/widgets/glass_card.dart';
import '../services/ticketcore_ai_service.dart';

class AITrainingScreen extends StatefulWidget {
  const AITrainingScreen({super.key});

  @override
  State<AITrainingScreen> createState() => _AITrainingScreenState();
}

class _AITrainingScreenState extends State<AITrainingScreen> {
  final TextEditingController _ruleNameCtrl = TextEditingController();
  final TextEditingController _ruleDetailCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiKeyCtrl.text = TicketCoreAIService.instance.geminiApiKey;
  }

  @override
  void dispose() {
    _ruleNameCtrl.dispose();
    _ruleDetailCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _addRule() {
    final name = _ruleNameCtrl.text.trim();
    final detail = _ruleDetailCtrl.text.trim();

    if (name.isEmpty || detail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both Rule Name and Detail instructions!'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      TicketCoreAIService.instance.addCustomTrainingRule(name, detail);
      _ruleNameCtrl.clear();
      _ruleDetailCtrl.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎓 AI Engine Trained with new rule "$name"!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _saveApiKey() {
    final key = _apiKeyCtrl.text.trim();
    TicketCoreAIService.instance.setGeminiApiKey(key);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(key.isEmpty ? 'Gemini API Key cleared. AI running in 100% offline mode.' : '⚡ Gemini API Key saved! Hybrid LLM Mode active.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rules = TicketCoreAIService.instance.customRules;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Row(
          children: [
            const Icon(Icons.school, color: AppColors.tertiary, size: 24),
            const SizedBox(width: 10),
            Text('AI TRAINING & KNOWLEDGE BASE ENGINE', style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.tertiaryContainer.withAlpha(30),
                borderRadius: AppDecorations.radiusLg,
                border: Border.all(color: AppColors.tertiary.withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.psychology, color: AppColors.tertiary, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TRAIN TICKETCORE AI KNOWLEDGE BASE', style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold, color: AppColors.tertiary)),
                        const SizedBox(height: 4),
                        Text(
                          'Add custom business rules, lottery formats, seller commission rules, and FAQs. The local AI engine learns these rules instantly with zero internet required.',
                          style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // 1. Add New Training Rule Section
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.add_task, color: AppColors.primary, size: 22),
                      const SizedBox(width: 8),
                      Text('ADD NEW AI TRAINING RULE / FAQ', style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Rule Topic / Trigger Keyword *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _ruleNameCtrl,
                              decoration: InputDecoration(
                                hintText: 'e.g. Commission Policy, Bumper Draw Rule',
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                                border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AI Instruction / Detail *', style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _ruleDetailCtrl,
                              decoration: InputDecoration(
                                hintText: 'e.g. Seller commission is 5% on Dear 1 PM and 7% on Evening Bumper',
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                                border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _addRule,
                      icon: const Icon(Icons.school, size: 18),
                      label: const Text('TRAIN AI RULE', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryContainer, foregroundColor: AppColors.onPrimaryContainer, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // 2. Active Trained Rules List
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.menu_book, color: AppColors.tertiary, size: 22),
                          const SizedBox(width: 8),
                          Text('ACTIVE TRAINED AI KNOWLEDGE RULES (${rules.length})', style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  rules.isEmpty
                      ? const Padding(padding: EdgeInsets.all(20.0), child: Center(child: Text('No trained rules added yet.')))
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: rules.length,
                          separatorBuilder: (ctx, i) => const Divider(color: AppColors.border, height: 24),
                          itemBuilder: (ctx, idx) {
                            final r = rules[idx];
                            return Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(6)),
                                  child: Text('${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.onPrimaryContainer)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(r['rule'] ?? '', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                      const SizedBox(height: 2),
                                      Text(r['detail'] ?? '', style: AppTypography.bodySm.copyWith(color: AppColors.textPrimary)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                                  tooltip: 'Delete Training Rule',
                                  onPressed: () {
                                    setState(() {
                                      TicketCoreAIService.instance.removeCustomTrainingRule(idx);
                                    });
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // 3. Optional Gemini API Key Configuration
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.key, color: Colors.amber, size: 22),
                      const SizedBox(width: 8),
                      Text('OPTIONAL: GOOGLE GEMINI LLM API KEY', style: AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold, color: Colors.amber)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Optional: If you want to enable deep generative chat alongside local offline engine, enter your Google Gemini API Key below. (Leave blank for 100% Free & Offline Mode).',
                    style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _apiKeyCtrl,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Enter optional Gemini API Key (e.g. AIzaSy...)',
                            filled: true,
                            fillColor: AppColors.surfaceContainerLow,
                            border: OutlineInputBorder(borderRadius: AppDecorations.radiusDefault, borderSide: const BorderSide(color: AppColors.border)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      ElevatedButton.icon(
                        onPressed: _saveApiKey,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('SAVE KEY', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.tertiaryContainer, foregroundColor: AppColors.onTertiaryContainer, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
