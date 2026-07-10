// lib/pages/lora_dataset_page.dart
// Admin page for managing the LoRA training dataset.
// Route: '/lora-dataset'
//
// Tabs:
//   1. Overview     — phase progress, stats, export
//   2. Recipes      — browse + add positive training pairs (Model A)
//   3. Compliance   — browse + generate negative examples (Model B)
//   4. Classifier   — browse food classifier pairs (Model C)
//   5. Validate     — run post-training validation

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bari_wise/models/lora_training_pair.dart';
import 'package:bari_wise/models/ingredient_matrix_entry.dart';
import 'package:bari_wise/services/lora_dataset_service.dart';
import 'package:bari_wise/services/lora_inference_service.dart';
import 'package:bari_wise/config/app_config.dart';
import 'dart:convert';

class LoraDatasetPage extends StatefulWidget {
  const LoraDatasetPage({super.key});

  @override
  State<LoraDatasetPage> createState() => _LoraDatasetPageState();
}

class _LoraDatasetPageState extends State<LoraDatasetPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<LoraTrainingPair> _allPairs   = [];
  Map<String, dynamic>  _stats      = {};
  bool                  _loading    = false;
  String                _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final stats = await LoraDatasetService.getDatasetStats();
    if (mounted) setState(() => _stats = stats);
  }

  Future<void> _generateNegativeExamples() async {
    setState(() {
      _loading       = true;
      _statusMessage = 'Generating 500 negative compliance examples...';
    });
    try {
      final pairs  = LoraDatasetService.generateNegativeExamplesDataset();
      final deduped = LoraDatasetService.deduplicate(pairs);
      await LoraDatasetService.saveDatasetStats(deduped);
      setState(() {
        _allPairs      = [..._allPairs, ...deduped];
        _statusMessage =
            '✅ Generated ${deduped.length} negative examples';
      });
      await _loadStats();
    } catch (e) {
      setState(() => _statusMessage = '❌ Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _generateClassifierDataset() async {
    setState(() {
      _loading       = true;
      _statusMessage = 'Generating food classifier training pairs...';
    });
    try {
      final pairs  = LoraDatasetService.generateClassifierDataset();
      final deduped = LoraDatasetService.deduplicate(pairs);
      await LoraDatasetService.saveDatasetStats(deduped);
      setState(() {
        _allPairs      = [..._allPairs, ...deduped];
        _statusMessage =
            '✅ Generated ${deduped.length} classifier pairs';
      });
      await _loadStats();
    } catch (e) {
      setState(() => _statusMessage = '❌ Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _exportDataset() async {
    setState(() {
      _loading       = true;
      _statusMessage = 'Exporting JSONL files...';
    });
    try {
      final exports = LoraDatasetService.exportToJsonl(_allPairs);
      final summary = exports.entries
          .map((e) =>
              '${e.key}: '
              '${e.value.split('\n').where((l) => l.isNotEmpty).length} '
              'pairs')
          .join('\n');

      final firstNonEmpty = exports.entries.firstWhere(
          (e) => e.value.isNotEmpty,
          orElse: () => const MapEntry('', ''));
      if (firstNonEmpty.value.isNotEmpty) {
        await Clipboard.setData(
            ClipboardData(text: firstNonEmpty.value));
      }

      setState(() => _statusMessage =
          '✅ Export ready:\n$summary\n\n'
          'First file copied to clipboard.');
    } catch (e) {
      setState(() => _statusMessage = '❌ Export error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _exportApprovedFromDB() async {
    setState(() {
      _loading       = true;
      _statusMessage = 'Fetching approved recipes from database...';
    });
    try {
      final pairs =
          await LoraDatasetService.exportApprovedRecipesAsTrainingPairs();
      final deduped = LoraDatasetService.deduplicate(pairs);
      await LoraDatasetService.saveDatasetStats(deduped);
      setState(() {
        _allPairs      = [..._allPairs, ...deduped];
        _statusMessage =
            '✅ Fetched ${deduped.length} approved recipe pairs from DB';
      });
      await _loadStats();
    } catch (e) {
      setState(() => _statusMessage = '❌ DB fetch error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _runValidation() async {
    setState(() {
      _loading       = true;
      _statusMessage = 'Running validation on generated recipes...';
    });
    try {
      final recipePairs = _allPairs
          .where((p) =>
              p.taskType == LoraTaskType.recipeGenerator &&
              p.output.generatedRecipe != null)
          .map((p) => p.output.generatedRecipe!)
          .toList();

      if (recipePairs.isEmpty) {
        setState(() {
          _statusMessage =
              '⚠️ No recipe pairs to validate yet. '
              'Export from DB first.';
          _loading = false;
        });
        return;
      }

      final report = await LoraInferenceService
          .validateGeneratedRecipes(recipePairs);

      setState(() => _statusMessage = report.summary);

      if (report.failures.isNotEmpty) {
        _showValidationFailures(report);
      }
    } catch (e) {
      setState(() => _statusMessage = '❌ Validation error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showValidationFailures(LoraValidationReport report) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
            'Validation Results — ${report.failed} failures'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: report.failures.length,
            itemBuilder: (ctx, i) {
              final f = report.failures[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.recipeName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      ...f.violations.map((v) => Text(
                            '• $v',
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12),
                          )),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LoRA Dataset Manager'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard),           text: 'Overview'),
            Tab(icon: Icon(Icons.restaurant),          text: 'Recipes'),
            Tab(icon: Icon(Icons.rule),                text: 'Compliance'),
            Tab(icon: Icon(Icons.local_grocery_store), text: 'Classifier'),
            Tab(icon: Icon(Icons.check_circle),        text: 'Validate'),
          ],
        ),
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(
                  stats:          _stats,
                  statusMessage:  _statusMessage,
                  allPairs:       _allPairs,
                  onExportDB:     _exportApprovedFromDB,
                  onExportJsonl:  _exportDataset,
                  onToggleLora:   (val) {
                    LoraInferenceService.setLoraEnabled(val);
                    setState(() {});
                  },
                  loraEnabled:    LoraInferenceService.isLoraEnabled,
                ),
                _RecipePairsTab(
                  pairs: _allPairs
                      .where((p) =>
                          p.taskType == LoraTaskType.recipeGenerator)
                      .toList(),
                ),
                _CompliancePairsTab(
                  pairs: _allPairs
                      .where((p) =>
                          p.taskType == LoraTaskType.complianceReviewer)
                      .toList(),
                  onGenerate: _generateNegativeExamples,
                ),
                _ClassifierTab(
                  pairs: _allPairs
                      .where((p) =>
                          p.taskType == LoraTaskType.foodClassifier)
                      .toList(),
                  onGenerate: _generateClassifierDataset,
                ),
                _ValidationTab(onRunValidation: _runValidation),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 1 — OVERVIEW
// ═══════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic>  stats;
  final String                statusMessage;
  final List<LoraTrainingPair> allPairs;
  final VoidCallback          onExportDB;
  final VoidCallback          onExportJsonl;
  final void Function(bool)   onToggleLora;
  final bool                  loraEnabled;

  const _OverviewTab({
    required this.stats,
    required this.statusMessage,
    required this.allPairs,
    required this.onExportDB,
    required this.onExportJsonl,
    required this.onToggleLora,
    required this.loraEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final recipeCount    = stats['recipe_pairs']     as int? ?? 0;
    final negativeCount  = stats['negative_pairs']   as int? ?? 0;
    final classifierCount = stats['classifier_pairs'] as int? ?? 0;

    final recipeTarget = stats['phase1_recipe_target'] as int? ??
        LoraDatasetService.phase1RecipeTarget;
    final negativeTarget = stats['phase1_negative_target'] as int? ??
        LoraDatasetService.phase1NegativeTarget;
    final classifierTarget =
        stats['phase1_classifier_target'] as int? ??
            LoraDatasetService.phase1ClassifierTarget;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status message
          if (statusMessage.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusMessage.startsWith('✅')
                    ? Colors.green.shade50
                    : statusMessage.startsWith('❌')
                        ? Colors.red.shade50
                        : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: statusMessage.startsWith('✅')
                      ? Colors.green.shade300
                      : statusMessage.startsWith('❌')
                          ? Colors.red.shade300
                          : Colors.blue.shade300,
                ),
              ),
              child: Text(statusMessage,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
            ),
            const SizedBox(height: 16),
          ],

          // LoRA feature flag toggle
          Card(
            child: SwitchListTile(
              title: const Text('LoRA Inference',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(loraEnabled
                  ? 'Active — recipe searches route to LoRA endpoint'
                  : 'Disabled — using database queries (safe default)'),
              value:       loraEnabled,
              onChanged:   onToggleLora,
              activeColor: Colors.deepPurple,
              secondary: Icon(
                loraEnabled
                    ? Icons.psychology
                    : Icons.psychology_outlined,
                color: loraEnabled
                    ? Colors.deepPurple
                    : Colors.grey,
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Text('Phase 1 Progress',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),

          _PhaseProgressCard(
            label:   'Model A — Recipe Generator',
            current: recipeCount,
            target:  recipeTarget,
            color:   Colors.blue,
            icon:    Icons.restaurant,
          ),
          const SizedBox(height: 8),
          _PhaseProgressCard(
            label:   'Model B — Compliance Reviewer',
            current: negativeCount,
            target:  negativeTarget,
            color:   Colors.orange,
            icon:    Icons.rule_folder,
          ),
          const SizedBox(height: 8),
          _PhaseProgressCard(
            label:   'Model C — Food Classifier',
            current: classifierCount,
            target:  classifierTarget,
            color:   Colors.green,
            icon:    Icons.local_grocery_store,
          ),

          const SizedBox(height: 24),
          const Text('Actions',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onExportDB,
              icon:  const Icon(Icons.cloud_download),
              label: const Text(
                  'Pull Approved Recipes from DB → Training Pairs'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onExportJsonl,
              icon:  const Icon(Icons.file_download),
              label: const Text(
                  'Export All as JSONL (Copy to Clipboard)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Ingredient matrix stats
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ingredient Matrix',
                      style:
                          TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    '${IngredientMatrix.entries.length} total entries  •  '
                    '${IngredientMatrix.beneficialCount} beneficial  •  '
                    '${IngredientMatrix.avoidForDisease("gastric_bypass").length} bypass-avoid  •  '
                    '${IngredientMatrix.preferredForDisease("gastric_bypass").length} bypass-preferred',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey),
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

class _PhaseProgressCard extends StatelessWidget {
  final String  label;
  final int     current;
  final int     target;
  final Color   color;
  final IconData icon;

  const _PhaseProgressCard({
    required this.label,
    required this.current,
    required this.target,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (current / target).clamp(0.0, 1.0);
    final pct      = (progress * 100).toInt();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
                Text('$current / $target',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:      progress,
                backgroundColor: Colors.grey.shade200,
                valueColor:
                    AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$pct% complete'
              '${current >= target ? " — ✅ Phase 1 target met" : ""}',
              style: TextStyle(
                  fontSize: 11,
                  color: current >= target
                      ? Colors.green
                      : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 2 — RECIPE PAIRS  (Model A)
// ═══════════════════════════════════════════════════════════════

class _RecipePairsTab extends StatelessWidget {
  final List<LoraTrainingPair> pairs;
  const _RecipePairsTab({required this.pairs});

  @override
  Widget build(BuildContext context) {
    if (pairs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No recipe training pairs yet',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Use the Overview tab to pull approved\n'
              'recipes from the database.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding:   const EdgeInsets.all(12),
      itemCount: pairs.length,
      itemBuilder: (ctx, i) {
        final pair   = pairs[i];
        final recipe = pair.output.generatedRecipe;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.restaurant,
                  color: Colors.blue.shade700),
            ),
            title: Text(recipe?.recipeName ?? pair.id,
                style: const TextStyle(
                    fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recipe != null) ...[
                  Text(
                    '${recipe.ingredients.length} ingredients • '
                    '${recipe.servings} servings',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'Score: ${recipe.compliance.healthScore}/100 • '
                    '${recipe.compliance.dietaryFlags.join(", ")}',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Model A',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
            onTap: () => _showPairDetail(ctx, pair),
          ),
        );
      },
    );
  }

  void _showPairDetail(BuildContext context, LoraTrainingPair pair) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
            pair.output.generatedRecipe?.recipeName ?? pair.id),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Instruction:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(pair.instruction,
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text('JSON Preview:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  JsonEncoder.withIndent('  ')
                      .convert(pair.toJson()),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: pair.toJsonLine()));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Copy JSONL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 3 — COMPLIANCE PAIRS  (Model B)
// ═══════════════════════════════════════════════════════════════

class _CompliancePairsTab extends StatelessWidget {
  final List<LoraTrainingPair> pairs;
  final VoidCallback           onGenerate;

  const _CompliancePairsTab(
      {required this.pairs, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    final sodiumCount = pairs
        .where((p) => p.id.contains('neg_sodium'))
        .length;
    final sugarCount = pairs
        .where((p) => p.id.contains('neg_sugar'))
        .length;
    final fatCount = pairs
        .where((p) => p.id.contains('neg_fat'))
        .length;
    final nutritionCount = pairs
        .where((p) => p.id.contains('neg_nutrition'))
        .length;
    final structCount = pairs
        .where((p) => p.id.contains('neg_struct'))
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pairs.isEmpty)
            ElevatedButton.icon(
              onPressed: onGenerate,
              icon:  const Icon(Icons.auto_fix_high),
              label: const Text(
                  'Generate 500 Negative Examples'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),

          const SizedBox(height: 16),

          if (pairs.isNotEmpty) ...[
            const Text('Violation Breakdown',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            _ViolationRow(
                label:  'Sodium violations',
                count:  sodiumCount,
                target: 100,
                color:  Colors.red),
            _ViolationRow(
                label:  'Sugar violations (dumping risk)',
                count:  sugarCount,
                target: 100,
                color:  Colors.pink),
            _ViolationRow(
                label:  'Fat violations',
                count:  fatCount,
                target: 100,
                color:  Colors.purple),
            _ViolationRow(
                label:  'Missing nutrition',
                count:  nutritionCount,
                target: 100,
                color:  Colors.orange),
            _ViolationRow(
                label:  'Structural errors',
                count:  structCount,
                target: 100,
                color:  Colors.brown),
            const SizedBox(height: 16),
            const Text(
              'Post-bariatric compliance thresholds:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            _ThresholdRow('Sodium',       '> 1500mg', Colors.red),
            _ThresholdRow('Sugar',        '> 25g (dumping risk)', Colors.pink),
            _ThresholdRow('Fat',          '> 45g',   Colors.purple),
            _ThresholdRow('Protein',      '< 15g/serving', Colors.blue),
            _ThresholdRow('Health Score', '< 50/100', Colors.orange),
            _ThresholdRow('Missing nutrition', 'null totalNutrition',
                Colors.brown),
          ],
        ],
      ),
    );
  }
}

class _ViolationRow extends StatelessWidget {
  final String label;
  final int    count;
  final int    target;
  final Color  color;

  const _ViolationRow({
    required this.label,
    required this.count,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Text(label,
                  style: const TextStyle(fontSize: 13))),
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (count / target).clamp(0.0, 1.0),
                backgroundColor: Colors.grey.shade200,
                valueColor:
                    AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$count/$target',
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  final String nutrient;
  final String threshold;
  final Color  color;

  const _ThresholdRow(this.nutrient, this.threshold, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width:  8,
            height: 8,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('$nutrient: ',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12)),
          Text(threshold,
              style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 4 — FOOD CLASSIFIER  (Model C)
// ═══════════════════════════════════════════════════════════════

class _ClassifierTab extends StatelessWidget {
  final List<LoraTrainingPair> pairs;
  final VoidCallback           onGenerate;

  const _ClassifierTab(
      {required this.pairs, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    final foodPairs = pairs
        .where((p) =>
            p.output.classificationResult?.isFood == true)
        .length;
    final nonFoodPairs = pairs.length - foodPairs;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pairs.isEmpty)
            ElevatedButton.icon(
              onPressed: onGenerate,
              icon:  const Icon(Icons.auto_awesome),
              label: const Text('Generate Classifier Dataset'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),

          if (pairs.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pairs.length} total pairs  •  '
                      '$foodPairs food  •  $nonFoodPairs non-food',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text('Sources:',
                        style: TextStyle(
                            fontWeight: FontWeight.w600)),
                    Text(
                      '• ${IngredientMatrix.entries.length} entries '
                      'from IngredientMatrix\n'
                      '• Aliases expand coverage to '
                      '~${IngredientMatrix.entries.fold(0, (sum, e) => sum + e.aliases.length + 1)} terms\n'
                      '• Non-food words from '
                      'FoodClassifierService._knownNonFoodWords',
                      style: const TextStyle(
                          fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Text('Categories',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),

            ...IngredientCategory.values.map((cat) {
              final count =
                  IngredientMatrix.byCategory(cat).length;
              if (count == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                        width: 120,
                        child: Text(cat.name,
                            style: const TextStyle(
                                fontSize: 12))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: count / 15.0,
                          backgroundColor: Colors.grey.shade200,
                          color: Colors.green,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('$count',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 5 — VALIDATION
// ═══════════════════════════════════════════════════════════════

class _ValidationTab extends StatelessWidget {
  final VoidCallback onRunValidation;
  const _ValidationTab({required this.onRunValidation});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.deepPurple.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.deepPurple.shade700),
                      const SizedBox(width: 8),
                      const Text('What validation checks:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Sodium ≤ 1500mg (post-bariatric limit)\n'
                    '• Sugar ≤ 25g (dumping syndrome prevention)\n'
                    '• Fat ≤ 45g (post-bariatric limit)\n'
                    '• Protein ≥ 15g per serving\n'
                    '• Health score ≥ 50/100\n'
                    '• Ingredients: {quantity, measurement, name} objects\n'
                    '• Directions: numbered steps separated by \\n\n'
                    '• Nutrition: all 7 required camelCase keys present\n'
                    '• Pass rate ≥ 95% required for production',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRunValidation,
              icon:  const Icon(Icons.play_circle),
              label: const Text(
                  'Run Validation on Generated Recipes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 24),

          const Text('Integration Checklist',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),

          ..._checklistItems.map((item) => _ChecklistItem(
                label:       item.$1,
                description: item.$2,
              )),
        ],
      ),
    );
  }

  static const _checklistItems = [
    (
      'SuggestedRecipesPage wired',
      'LoraInferenceService.searchRecipes() called before Worker DB query'
    ),
    (
      'FoodClassifierService patched',
      'LoraInferenceService.tryClassifyWord() inserted before _tryGroq()'
    ),
    (
      'SubmitRecipePage pre-screen added',
      'LoraInferenceService.prescreenCompliance() called before submission'
    ),
    (
      'Dataset JSONL exported',
      'lora_recipes_v1.jsonl + lora_compliance_v1.jsonl + lora_classifier_v1.jsonl'
    ),
    (
      'Python pipeline ready',
      '/scripts/export_training_data.py matches Worker query params'
    ),
    (
      'Worker /lora/* endpoints deployed',
      'Cloudflare Worker serving LoRA inference at /lora/recipes/search etc.'
    ),
    (
      'Validation ≥ 95%',
      'Run validation tab before flipping _loraEnabled = true'
    ),
  ];
}

class _ChecklistItem extends StatelessWidget {
  final String label;
  final String description;

  const _ChecklistItem(
      {required this.label, required this.description});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_box_outline_blank,
              size: 20, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                Text(description,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}