/// Who a chat message came from.
enum ChatRole { user, ai }

/// A single message in the AI Assistant chat. Purely in-memory — chat
/// history is not persisted to Supabase or disk (no schema change
/// required), matching "reuse existing services, don't add tables unless
/// required" from the feature request.
class ChatMessage {
  final String id;
  final ChatRole role;
  final String text;
  final DateTime timestamp;
  final List<String> suggestedActions;
  final bool isError;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.suggestedActions = const [],
    this.isError = false,
  }) : timestamp = timestamp ?? DateTime.now();
}
