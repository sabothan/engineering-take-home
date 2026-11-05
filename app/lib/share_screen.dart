import 'package:flutter/material.dart';

import 'api.dart';
import 'format.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

const _periods = [
  (label: 'Last 7 days', days: 7),
  (label: 'Last 14 days', days: 14),
  (label: 'Last 30 days', days: 30),
];

enum _Step { form, review }

/// Lets the patient pick a doctor, a period and whether to include notes, review exactly what
/// that doctor will be able to see (O.Purp_1), and then share.
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  late Future<List<Clinician>> _clinicians = widget.api.listClinicians();

  _Step _step = _Step.form;
  int? _clinicianId;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _includeNotes = false;
  bool _saving = false;

  void _pickPeriod(int days) {
    final today = DateTime.now();
    final to = DateTime(today.year, today.month, today.day);
    setState(() {
      _toDate = to;
      _fromDate = to.subtract(Duration(days: days - 1));
    });
  }

  Future<void> _pickCustomRange() async {
    final today = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );
    if (range == null) return;
    setState(() {
      _fromDate = DateTime(range.start.year, range.start.month, range.start.day);
      _toDate = DateTime(range.end.year, range.end.month, range.end.day);
    });
  }

  bool get _canReview => _clinicianId != null && _fromDate != null && _toDate != null;

  Future<void> _confirmShare(Clinician clinician) async {
    setState(() => _saving = true);
    try {
      await widget.api.createShare(
        clinicianId: clinician.id,
        fromDate: _fromDate!,
        toDate: _toDate!,
        includeNotes: _includeNotes,
      );
      widget.api.track('share_created');
      if (mounted) Navigator.of(context).pop(true);
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't share your diary. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: FutureBuilder(
          future: _clinicians,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Message(
                title: "Couldn't load your doctors",
                body: 'Check your connection and try again.',
                action: TextButton(
                  onPressed: () => setState(() => _clinicians = widget.api.listClinicians()),
                  child: const Text('Try again'),
                ),
              );
            }
            final clinicians = snapshot.data;
            if (clinicians == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final selected = _clinicianId == null
                ? null
                : clinicians.firstWhere((c) => c.id == _clinicianId);
            return _step == _Step.form
                ? _FormStep(
                    clinicians: clinicians,
                    selectedId: _clinicianId,
                    fromDate: _fromDate,
                    toDate: _toDate,
                    includeNotes: _includeNotes,
                    canContinue: _canReview,
                    onSelectClinician: (id) => setState(() => _clinicianId = id),
                    onPickPeriod: _pickPeriod,
                    onPickCustomRange: _pickCustomRange,
                    onIncludeNotesChanged: (value) => setState(() => _includeNotes = value),
                    onContinue: () => setState(() => _step = _Step.review),
                  )
                : _ReviewStep(
                    clinician: selected!,
                    fromDate: _fromDate!,
                    toDate: _toDate!,
                    includeNotes: _includeNotes,
                    saving: _saving,
                    onEdit: () => setState(() => _step = _Step.form),
                    onConfirm: () => _confirmShare(selected),
                  );
          },
        ),
      ),
    );
  }
}

class _FormStep extends StatelessWidget {
  const _FormStep({
    required this.clinicians,
    required this.selectedId,
    required this.fromDate,
    required this.toDate,
    required this.includeNotes,
    required this.canContinue,
    required this.onSelectClinician,
    required this.onPickPeriod,
    required this.onPickCustomRange,
    required this.onIncludeNotesChanged,
    required this.onContinue,
  });

  final List<Clinician> clinicians;
  final int? selectedId;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool includeNotes;
  final bool canContinue;
  final ValueChanged<int> onSelectClinician;
  final ValueChanged<int> onPickPeriod;
  final VoidCallback onPickCustomRange;
  final ValueChanged<bool> onIncludeNotesChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Space.m),
            children: [
              ContentColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Share with a doctor', style: text.headlineMedium),
                    const SizedBox(height: Space.xl),
                    Text('Doctor', style: text.titleMedium),
                    const SizedBox(height: Space.s),
                    for (final clinician in clinicians)
                      _ClinicianOption(
                        clinician: clinician,
                        selected: clinician.id == selectedId,
                        onTap: () => onSelectClinician(clinician.id),
                      ),
                    const SizedBox(height: Space.xl),
                    Text('Period', style: text.titleMedium),
                    const SizedBox(height: Space.s),
                    Wrap(
                      spacing: Space.s,
                      runSpacing: Space.s,
                      children: [
                        for (final preset in _periods)
                          FilterChip(
                            label: Text(preset.label),
                            selected: _isPreset(preset.days),
                            onSelected: (_) => onPickPeriod(preset.days),
                          ),
                        FilterChip(
                          label: const Text('Custom range'),
                          selected: fromDate != null && toDate != null && !_isAnyPreset(),
                          onSelected: (_) => onPickCustomRange(),
                        ),
                      ],
                    ),
                    if (fromDate != null && toDate != null) ...[
                      const SizedBox(height: Space.s),
                      Text(formatDateRange(fromDate!, toDate!), style: text.bodyLarge),
                    ],
                    const SizedBox(height: Space.xl),
                    Text('Notes', style: text.titleMedium),
                    const SizedBox(height: Space.s),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Also share the private notes you wrote with your entries.',
                            style: text.bodyMedium,
                          ),
                        ),
                        Switch(value: includeNotes, onChanged: onIncludeNotesChanged),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: ContentColumn(
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: FilledButton(
                onPressed: canContinue ? onContinue : null,
                child: const Text('Review and share'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _isAnyPreset() => _periods.any((preset) => _isPreset(preset.days));

  bool _isPreset(int days) {
    if (fromDate == null || toDate == null) return false;
    final today = DateTime.now();
    final expectedTo = DateTime(today.year, today.month, today.day);
    final expectedFrom = expectedTo.subtract(Duration(days: days - 1));
    return fromDate == expectedFrom && toDate == expectedTo;
  }
}

class _ClinicianOption extends StatelessWidget {
  const _ClinicianOption({required this.clinician, required this.selected, required this.onTap});

  final Clinician clinician;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${clinician.name}, ${clinician.practice}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: Space.s),
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.card,
            border: Border.all(
              color: selected ? AppColors.ink : AppColors.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(clinician.name, style: text.labelLarge),
                    Text(clinician.practice, style: text.bodyMedium),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.clinician,
    required this.fromDate,
    required this.toDate,
    required this.includeNotes,
    required this.saving,
    required this.onEdit,
    required this.onConfirm,
  });

  final Clinician clinician;
  final DateTime fromDate;
  final DateTime toDate;
  final bool includeNotes;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final categories = includeNotes ? 'Mood, symptoms and notes' : 'Mood and symptoms';
    final period = formatDateRange(fromDate, toDate);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Space.m),
            children: [
              ContentColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Review and share', style: text.headlineMedium),
                    const SizedBox(height: Space.l),
                    Text('Doctor', style: text.titleMedium),
                    const SizedBox(height: Space.xs),
                    Text('${clinician.name}, ${clinician.practice}', style: text.bodyLarge),
                    const SizedBox(height: Space.l),
                    Text('What they can see', style: text.titleMedium),
                    const SizedBox(height: Space.xs),
                    Text(categories, style: text.bodyLarge),
                    const SizedBox(height: Space.l),
                    Text('Period', style: text.titleMedium),
                    const SizedBox(height: Space.xs),
                    Text(period, style: text.bodyLarge),
                    const SizedBox(height: Space.xl),
                    Text(
                      '${clinician.name} will be able to read this from $period. '
                      'You can stop sharing at any time.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: Space.m),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(onPressed: onEdit, child: const Text('Edit selection')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: ContentColumn(
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: FilledButton(
                onPressed: saving ? null : onConfirm,
                child: const Text('Share diary'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
