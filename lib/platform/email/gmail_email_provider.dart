import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;

import 'email_provider.dart';

/// Gmail-metadata-only implementation. Uses the narrowest scope Google
/// offers (`gmail.metadata`) rather than `gmail.readonly` — this app only
/// ever needs to know *that* a message was exchanged and *when*, never
/// its subject or body, per DESIGN.md §10's privacy posture. That scope
/// restriction also means [gmail.Message.payload] is never populated in
/// responses here; only headers.
///
/// Requires an OAuth client registered in Google Cloud Console before
/// this can authenticate for real — see DESIGN.md §11.
class GmailEmailProvider implements EmailProvider {
  GmailEmailProvider({GoogleSignIn? signIn})
      : _signIn = signIn ??
            GoogleSignIn(scopes: [
              'https://www.googleapis.com/auth/gmail.metadata',
            ]);

  final GoogleSignIn _signIn;
  gmail.GmailApi? _api;

  @override
  Future<bool> isConnected() async {
    final account = await _signIn.signInSilently();
    if (account == null) return false;
    _api ??= await _buildApi(account);
    return true;
  }

  @override
  Future<bool> connect() async {
    final account = await _signIn.signIn();
    if (account == null) return false;
    _api = await _buildApi(account);
    return true;
  }

  @override
  Future<void> disconnect() async {
    await _signIn.signOut();
    _api = null;
  }

  Future<gmail.GmailApi> _buildApi(GoogleSignInAccount account) async {
    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    return gmail.GmailApi(client);
  }

  @override
  Future<List<EmailFrequencyEvent>> fetchEventsSince(
    List<String> addresses,
    DateTime since,
  ) async {
    final api = _api;
    if (api == null || addresses.isEmpty) return [];

    final afterEpochDay = since.millisecondsSinceEpoch ~/ 86400000;
    final addressQuery = addresses.map((a) => '(from:$a OR to:$a)').join(' OR ');
    final query = '($addressQuery) after:$afterEpochDay';

    final events = <EmailFrequencyEvent>[];
    String? pageToken;

    do {
      final listResult = await api.users.messages.list(
        'me',
        q: query,
        pageToken: pageToken,
        maxResults: 100,
      );
      pageToken = listResult.nextPageToken;

      for (final ref in listResult.messages ?? const []) {
        if (ref.id == null) continue;
        // Headers only — gmail.metadata scope enforces this server-side
        // too, but requesting metadata format explicitly documents intent.
        final message = await api.users.messages.get(
          'me',
          ref.id!,
          format: 'metadata',
          metadataHeaders: ['From', 'To', 'Date'],
        );

        final headers = message.payload?.headers ?? const [];
        final dateHeader = headers.where((h) => h.name == 'Date').firstOrNull;
        final fromHeader = headers.where((h) => h.name == 'From').firstOrNull;
        final toHeader = headers.where((h) => h.name == 'To').firstOrNull;

        final timestamp = _parseDate(dateHeader?.value) ??
            DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(message.internalDate ?? '') ?? 0,
            );

        final counterpart = _firstMatchingAddress(
          [fromHeader?.value, toHeader?.value],
          addresses,
        );
        if (counterpart == null) continue;

        events.add(
          EmailFrequencyEvent(
            counterpartAddress: counterpart,
            timestamp: timestamp,
          ),
        );
      }
    } while (pageToken != null);

    return events;
  }

  DateTime? _parseDate(String? rfc2822) {
    if (rfc2822 == null) return null;
    try {
      return DateTime.parse(rfc2822);
    } catch (_) {
      return null; // RFC 2822 isn't always ISO-parseable; good enough for v1
    }
  }

  String? _firstMatchingAddress(
    List<String?> headerValues,
    List<String> tracked,
  ) {
    for (final value in headerValues) {
      if (value == null) continue;
      for (final address in tracked) {
        if (value.toLowerCase().contains(address.toLowerCase())) {
          return address;
        }
      }
    }
    return null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Wraps Google Sign-In's auth headers into an [http.Client] the
/// generated `googleapis` client can use.
class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
