import 'package:flutter/material.dart';

import 'theme.dart';

/// Centres a screen's content and caps its width (see DESIGN.md, Layout).
class ContentColumn extends StatelessWidget {
  const ContentColumn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Space.maxContentWidth),
        child: child,
      ),
    );
  }
}

/// A small pill for a symptom name.
class SymptomTag extends StatelessWidget {
  const SymptomTag(this.symptom, {super.key});

  final String symptom;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: const ShapeDecoration(
        color: AppColors.paper,
        shape: StadiumBorder(side: BorderSide(color: AppColors.line)),
      ),
      child: Text(sentenceCase(symptom), style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

String sentenceCase(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// A centred title + body, optionally with an action — for empty and error states.
class Message extends StatelessWidget {
  const Message({super.key, required this.title, required this.body, this.action});

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ContentColumn(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xl),
        child: Column(
          children: [
            Text(title, style: text.titleMedium),
            const SizedBox(height: Space.xs),
            Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// A white card for one record in a list (e.g. a share or a clinician) — like [EntryCard] but
/// without the mood rail, per DESIGN.md.
class RecordCard extends StatelessWidget {
  const RecordCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      padding: const EdgeInsets.all(Space.m),
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: Radii.card),
      child: child,
    );
  }
}
