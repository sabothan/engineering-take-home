import 'package:flutter/material.dart';

import 'access_log_screen.dart';
import 'api.dart';
import 'format.dart';
import 'models.dart';
import 'share_screen.dart';
import 'theme.dart';
import 'widgets.dart';

typedef _SharingData = ({List<Share> shares, List<Clinician> clinicians});

/// Lists who the patient has shared their diary with, lets them stop sharing, and links to
/// who's looked at it (O.Log_2) and to starting a new share.
class SharingScreen extends StatefulWidget {
  const SharingScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends State<SharingScreen> {
  late Future<_SharingData> _data = _load();

  Future<_SharingData> _load() async {
    final shares = await widget.api.listShares();
    final clinicians = await widget.api.listClinicians();
    return (shares: shares, clinicians: clinicians);
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _share() async {
    final shared = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => ShareScreen(api: widget.api)));
    if (shared == true) _reload();
  }

  Future<void> _revoke(Share share, Clinician? clinician) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop sharing?'),
        content: Text(
          '${clinician?.name ?? 'This doctor'} will no longer be able to read your diary.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke access'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.revokeShare(share.id);
      widget.api.track('share_revoked');
      _reload();
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't stop sharing. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _share,
        icon: const Icon(Icons.add),
        label: const Text('Share with a doctor'),
      ),
      body: SafeArea(
        child: FutureBuilder(
          future: _data,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, 96),
                children: [
                  ContentColumn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sharing', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: Space.s),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => AccessLogScreen(api: widget.api)),
                            ),
                            child: const Text('Who saw your diary'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  if (snapshot.hasError)
                    Message(
                      title: "Couldn't load your shares",
                      body: 'Check your connection and try again.',
                      action: TextButton(onPressed: _reload, child: const Text('Try again')),
                    )
                  else if (data == null)
                    const Center(child: CircularProgressIndicator())
                  else if (data.shares.isEmpty)
                    const Message(
                      title: "You haven't shared your diary yet",
                      body: 'Share it with a doctor before your next appointment.',
                    )
                  else
                    ContentColumn(
                      child: Column(
                        children: [
                          for (final share in data.shares)
                            _ShareCard(
                              share: share,
                              clinician: _clinicianFor(data.clinicians, share.clinicianId),
                              onRevoke: () => _revoke(
                                share,
                                _clinicianFor(data.clinicians, share.clinicianId),
                              ),
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
    );
  }

  Clinician? _clinicianFor(List<Clinician> clinicians, int id) {
    for (final clinician in clinicians) {
      if (clinician.id == id) return clinician;
    }
    return null;
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.share, required this.clinician, required this.onRevoke});

  final Share share;
  final Clinician? clinician;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return RecordCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(clinician?.name ?? 'Doctor', style: text.labelLarge),
          if (clinician != null) Text(clinician!.practice, style: text.bodyMedium),
          const SizedBox(height: Space.s),
          Text(formatDateRange(share.fromDate, share.toDate), style: text.bodyLarge),
          const SizedBox(height: Space.xs),
          Text(
            share.includeNotes ? 'Mood, symptoms and notes' : 'Mood and symptoms',
            style: text.labelMedium,
          ),
          const SizedBox(height: Space.s),
          Align(
            alignment: Alignment.centerRight,
            child: share.isActive
                ? TextButton(onPressed: onRevoke, child: const Text('Revoke access'))
                : Text(
                    'Revoked on ${formatDate(share.revokedAt!.toLocal())}',
                    style: text.labelMedium,
                  ),
          ),
        ],
      ),
    );
  }
}
