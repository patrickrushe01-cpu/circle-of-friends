/// One send-or-receive event with a specific email address, counted for
/// frequency only — per DESIGN.md §10, message content is never read.
class EmailFrequencyEvent {
  const EmailFrequencyEvent({
    required this.counterpartAddress,
    required this.timestamp,
  });

  final String counterpartAddress;
  final DateTime timestamp;
}

/// Abstraction over "wherever email frequency comes from," so the
/// collector and scoring pipeline don't care whether it's Gmail, an IMAP
/// mailbox, or (in tests) a fake. [GmailEmailProvider] is the only
/// implementation in this scaffold; a generic IMAP provider is future
/// work noted in DESIGN.md.
abstract class EmailProvider {
  Future<bool> isConnected();

  /// Kicks off whatever auth flow this provider needs (OAuth consent,
  /// etc). Returns true if the app is left connected afterward.
  Future<bool> connect();

  Future<void> disconnect();

  /// Returns one event per message sent or received with any of
  /// [addresses], since [since]. Implementations must fetch headers only
  /// (sender/recipient/date) — never message bodies.
  Future<List<EmailFrequencyEvent>> fetchEventsSince(
    List<String> addresses,
    DateTime since,
  );
}
