import 'dart:convert';

import 'package:diary_app/access_log_screen.dart';
import 'package:diary_app/api.dart';
import 'package:diary_app/main.dart';
import 'package:diary_app/sharing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final clinician1 = {'id': 1, 'name': 'Dr. Lena Hofmann', 'practice': 'Praxis Hofmann, München'};

/// http.Response picks latin1 by default unless the content-type says otherwise, which mangles
/// non-ASCII fixtures like "München" on decode. Declare JSON explicitly so it picks utf8.
http.Response _jsonResponse(dynamic body, int statusCode) =>
    http.Response(jsonEncode(body), statusCode, headers: {'content-type': 'application/json'});

/// An in-memory stand-in for the diary API, extended with sharing endpoints.
MockClient fakeApi({
  List<Map<String, dynamic>> clinicians = const [],
  List<Map<String, dynamic>> shares = const [],
  List<Map<String, dynamic>> accessLog = const [],
  List<http.Request>? log,
}) {
  final sharesState = [...shares];
  return MockClient((request) async {
    log?.add(request);
    final path = request.url.path;
    final segments = request.url.pathSegments;

    if (request.method == 'GET' && path.endsWith('/entries')) {
      return _jsonResponse(const [], 200);
    }
    if (request.method == 'GET' && path.endsWith('/clinicians')) {
      return _jsonResponse(clinicians, 200);
    }
    if (request.method == 'POST' && path.endsWith('/shares')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final share = {
        'id': sharesState.length + 1,
        'clinician_id': body['clinician_id'],
        'from_date': body['from_date'],
        'to_date': body['to_date'],
        'include_notes': body['include_notes'] ?? false,
        'created_at': '2026-10-08T09:12:00Z',
        'revoked_at': null,
      };
      sharesState.insert(0, share);
      return _jsonResponse(share, 201);
    }
    if (request.method == 'POST' &&
        segments.length >= 2 &&
        segments[segments.length - 1] == 'revoke') {
      final id = int.parse(segments[segments.length - 2]);
      final share = sharesState.firstWhere((s) => s['id'] == id);
      share['revoked_at'] = '2026-10-09T09:00:00Z';
      return _jsonResponse(share, 200);
    }
    if (request.method == 'GET' && path.endsWith('/shares')) {
      return _jsonResponse(sharesState, 200);
    }
    if (request.method == 'GET' && path.endsWith('/access-log')) {
      return _jsonResponse(accessLog, 200);
    }
    if (request.method == 'POST' && path.endsWith('/telemetry')) {
      return http.Response('', 204);
    }
    return http.Response('Not found', 404);
  });
}

void main() {
  testWidgets('shares the diary with a doctor, reviewing before confirming', (tester) async {
    final requests = <http.Request>[];
    final api = ApiClient(client: fakeApi(clinicians: [clinician1], log: requests));

    await tester.pumpWidget(DiaryApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pumpAndSettle();
    expect(find.text("You haven't shared your diary yet"), findsOneWidget);

    await tester.tap(find.text('Share with a doctor'));
    await tester.pumpAndSettle();

    // Nothing to review yet: the button is disabled until a doctor and a period are picked.
    await tester.tap(find.text('Review and share'));
    await tester.pumpAndSettle();
    expect(find.text('Review and share'), findsOneWidget); // still on the form step

    await tester.tap(find.text('Dr. Lena Hofmann'));
    await tester.pump();
    await tester.tap(find.text('Last 7 days'));
    await tester.pump();
    await tester.tap(find.text('Review and share'));
    await tester.pumpAndSettle();

    // The review step must show recipient, data categories and period before sharing (O.Purp_1).
    expect(find.text('Dr. Lena Hofmann, Praxis Hofmann, München'), findsOneWidget);
    expect(find.text('Mood and symptoms'), findsOneWidget);
    expect(find.text('Share diary'), findsOneWidget);

    await tester.tap(find.text('Share diary'));
    await tester.pumpAndSettle();

    // Back on the sharing list, now showing the new share instead of the empty state.
    expect(find.text("You haven't shared your diary yet"), findsNothing);
    expect(find.text('Dr. Lena Hofmann'), findsOneWidget);
    expect(find.text('Revoke access'), findsOneWidget);

    final created = jsonDecode(
      requests.firstWhere((r) => r.method == 'POST' && r.url.path.endsWith('/shares')).body,
    );
    expect(created['clinician_id'], 1);
    expect(created['include_notes'], false);
    expect(
      requests.where((r) => r.url.path.endsWith('/telemetry')).single.body,
      contains('share_created'),
    );
  });

  testWidgets('stops sharing with a doctor', (tester) async {
    final requests = <http.Request>[];
    final api = ApiClient(
      client: fakeApi(
        clinicians: [clinician1],
        shares: [
          {
            'id': 7,
            'clinician_id': 1,
            'from_date': '2026-10-01',
            'to_date': '2026-10-07',
            'include_notes': false,
            'created_at': '2026-10-01T09:00:00Z',
            'revoked_at': null,
          },
        ],
        log: requests,
      ),
    );

    await tester.pumpWidget(MaterialApp(home: SharingScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Revoke access'), findsOneWidget);
    await tester.tap(find.text('Revoke access'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Revoke access')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Revoke access'), findsNothing);
    expect(find.textContaining('Revoked on'), findsOneWidget);
    expect(
      requests.any((r) => r.method == 'POST' && r.url.path.endsWith('/shares/7/revoke')),
      isTrue,
    );
  });

  testWidgets('shows who saw the diary, and when', (tester) async {
    final api = ApiClient(
      client: fakeApi(
        accessLog: [
          {
            'clinician_id': 1,
            'clinician_name': 'Dr. Lena Hofmann',
            'accessed_at': '2026-10-08T10:03:00Z',
            'entry_ids': [3, 5],
          },
        ],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: AccessLogScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Dr. Lena Hofmann'), findsOneWidget);
    expect(find.text('Looked at 2 entries'), findsOneWidget);
  });

  testWidgets('empty access log invites the patient to share first', (tester) async {
    final api = ApiClient(client: fakeApi());

    await tester.pumpWidget(MaterialApp(home: AccessLogScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('No one has looked at your diary yet'), findsOneWidget);
  });
}
