import 'package:flutter/material.dart';

import 'api.dart';
import 'format.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shows the patient who read their diary, and when (O.Log_2).
class AccessLogScreen extends StatefulWidget {
  const AccessLogScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<AccessLogScreen> createState() => _AccessLogScreenState();
}

class _AccessLogScreenState extends State<AccessLogScreen> {
  late Future<List<AccessLogEntry>> _log = widget.api.listAccessLog();

  void _reload() {
    setState(() {
      _log = widget.api.listAccessLog();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: FutureBuilder(
          future: _log,
          builder: (context, snapshot) {
            final log = snapshot.data;
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, Space.l),
                children: [
                  ContentColumn(
                    child: Text('Who saw your diary', style: Theme.of(context).textTheme.headlineMedium),
                  ),
                  const SizedBox(height: Space.l),
                  if (snapshot.hasError)
                    Message(
                      title: "Couldn't load this",
                      body: 'Check your connection and try again.',
                      action: TextButton(onPressed: _reload, child: const Text('Try again')),
                    )
                  else if (log == null)
                    const Center(child: CircularProgressIndicator())
                  else if (log.isEmpty)
                    const Message(
                      title: 'No one has looked at your diary yet',
                      body: "You'll see it here as soon as a doctor opens a diary you shared.",
                    )
                  else
                    ContentColumn(
                      child: Column(
                        children: [for (final entry in log) _AccessCard(entry)],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard(this.entry);

  final AccessLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return RecordCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.clinicianName, style: text.labelLarge),
          const SizedBox(height: Space.xs),
          Text(formatDateTime(entry.accessedAt), style: text.bodyMedium),
          const SizedBox(height: Space.xs),
          Text(_summary(entry.entryIds.length), style: text.labelMedium),
        ],
      ),
    );
  }

  String _summary(int count) {
    if (count == 0) return "Didn't see any entries";
    if (count == 1) return 'Looked at 1 entry';
    return 'Looked at $count entries';
  }
}
