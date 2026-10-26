import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:finora/models/ai_avatar.dart';
import 'package:finora/models/chat_message.dart';
import 'package:finora/models/expense.dart';
import 'package:finora/models/onboarding_record.dart';
import 'package:finora/models/profile.dart';
import 'package:finora/services/ai_avatar_service.dart';
import 'package:finora/services/ai_chat_service.dart';
import 'package:finora/services/auth_provider.dart';
import 'package:finora/services/onboarding_service.dart';
import 'package:finora/services/profile_service.dart';
import 'package:finora/services/spending_lock_provider.dart';
import 'package:finora/services/supabase_service.dart';
import 'package:finora/utils/theme.dart';
import 'package:finora/widgets/glass_card.dart';

/// Dedicated "Finora - Assistant" chat screen.
///
/// New feature only — does not touch auth, onboarding, dashboard, the
/// Supabase schema, or existing navigation. Reuses ProfileService,
/// OnboardingService, SupabaseService, SpendingLockProvider and the app
/// theme exactly as the rest of the app does.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final AIChatService _chatService = DemoAIChatService();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  bool _loadingContext = true;
  String? _contextError;
  String? _avatarId;
  AiChatContext? _ctx;
  String? _userId;

  final List<ChatMessage> _messages = [];
  bool _thinking = false;
  int _msgCounter = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    debugPrint('AI Assistant: started');
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }
    _userId = user.id;

    Profile? profile;
    OnboardingRecord? onboarding;
    List<Expense> expenses = const [];
    BudgetLimits limits = BudgetLimits();
    String? avatarId;

    try {
      avatarId = await AiAvatarService.getSelected(user.id);
    } catch (e) {
      debugPrint('AI Assistant: avatar load failed (non-fatal): $e');
    }

    try {
      profile = await ProfileService.getProfile(user.id);
    } catch (e) {
      debugPrint('AI Assistant: profile load failed (non-fatal): $e');
    }

    try {
      onboarding = await OnboardingService.getOnboarding(user.id);
    } catch (e) {
      debugPrint('AI Assistant: onboarding load failed (non-fatal): $e');
    }

    try {
      expenses = await SupabaseService.getExpenses(user.id);
    } catch (e) {
      debugPrint('AI Assistant: expenses load failed (non-fatal): $e');
    }

    try {
      final loadedLimits = await SupabaseService.getBudgetLimits(user.id);
      if (loadedLimits != null) limits = loadedLimits;
    } catch (e) {
      debugPrint('AI Assistant: budget limits load failed (non-fatal): $e');
    }

    // SpendingLockProvider may not be loaded yet if the user opened this
    // screen without visiting the dashboard first — load it defensively,
    // but never let a failure here block the chat from opening.
    try {
      final lockProvider = context.read<SpendingLockProvider>();
      if (lockProvider.lock == null) {
        await lockProvider.load(user.id, limits.savingsGoal);
      }
    } catch (e) {
      debugPrint('AI Assistant: SafeLock load failed (non-fatal): $e');
    }

    if (!mounted) return;

    if (profile == null || onboarding == null) {
      setState(() {
        _loadingContext = false;
        _contextError =
            'I couldn\'t load your financial data right now, so my answers '
            'may be limited. You can still chat — try again in a moment for '
            'fuller context.';
        _avatarId = avatarId;
      });
      debugPrint('AI Assistant: ready (limited context)');
      return;
    }

    final lockProvider = context.read<SpendingLockProvider>();
    setState(() {
      _ctx = AiChatContext(
        profile: profile!,
        onboarding: onboarding!,
        expenses: expenses,
        limits: limits,
        safeLockWarningCount: lockProvider.warningCount,
        safeLockActive: lockProvider.isLocked || lockProvider.isStrictLocked,
      );
      _avatarId = avatarId;
      _loadingContext = false;
    });
    debugPrint('AI Assistant: ready');
  }

  Future<void> _selectAvatar(String id) async {
    setState(() => _avatarId = id);
    if (_userId != null) {
      await AiAvatarService.setSelected(_userId!, id);
    }
  }

  void _changeAvatar() {
    setState(() => _avatarId = null);
  }

  Future<void> _send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _thinking) return;

    setState(() {
      _messages.add(ChatMessage(
        id: 'm${_msgCounter++}',
        role: ChatRole.user,
        text: text,
      ));
      _thinking = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    try {
      if (_ctx == null) {
        throw StateError('No financial context available yet');
      }
      final reply = await _chatService
          .ask(text, _ctx!)
          .timeout(const Duration(seconds: 8));
      // Small artificial pause so the "thinking" state reads naturally —
      // the rule-based lookup itself is effectively instant.
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          id: 'm${_msgCounter++}',
          role: ChatRole.ai,
          text: reply.text,
          suggestedActions: reply.suggestedActions,
        ));
        _thinking = false;
      });
    } catch (e) {
      debugPrint('AI Assistant: reply failed: $e');
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          id: 'm${_msgCounter++}',
          role: ChatRole.ai,
          text: 'Sorry, something went wrong generating a reply. Please try again.',
          isError: true,
        ));
        _thinking = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _onActionChip(String action) {
    switch (action) {
      case 'View Budget':
        _send('Show my budget');
        break;
      case 'Reduce Expenses':
        _send('How can I save more?');
        break;
      case 'Investment Advice':
        _send('Give me investment advice');
        break;
      default:
        _send(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatar = AiAvatars.byId(_avatarId);
    final lock = context.watch<SpendingLockProvider>();
    final showSafeLockBanner = _avatarId != null &&
        !_loadingContext &&
        (lock.isLocked || lock.isStrictLocked || lock.warningCount > 0);

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              avatar: avatar,
              isDark: isDark,
              showChangeAvatar: _avatarId != null,
              onChangeAvatar: _changeAvatar,
              avatarState: _thinking ? AiAvatarState.thinking : AiAvatarState.idle,
            ),
            if (showSafeLockBanner) _SafeLockBanner(lock: lock, isDark: isDark),
            if (_contextError != null && _avatarId != null)
              _ErrorBanner(text: _contextError!, isDark: isDark),
            Expanded(
              child: _loadingContext
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _avatarId == null
                      ? _AvatarSelectionView(isDark: isDark, onSelect: _selectAvatar)
                      : _ChatView(
                          scrollCtrl: _scrollCtrl,
                          messages: _messages,
                          thinking: _thinking,
                          avatar: avatar,
                          isDark: isDark,
                          onQuickQuestion: _send,
                          onActionChip: _onActionChip,
                        ),
            ),
            if (!_loadingContext && _avatarId != null)
              _ChatInputBar(
                controller: _inputCtrl,
                isDark: isDark,
                enabled: !_thinking,
                onSend: _send,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AiAvatarOption avatar;
  final bool isDark;
  final bool showChangeAvatar;
  final VoidCallback onChangeAvatar;
  final AiAvatarState avatarState;

  const _Header({
    required this.avatar,
    required this.isDark,
    required this.showChangeAvatar,
    required this.onChangeAvatar,
    required this.avatarState,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark).withOpacity(0.6),
        border: Border(bottom: BorderSide(color: AppTheme.border(isDark))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppTheme.fg(isDark),
            onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
          ),
          _AiAvatarOrb(avatar: avatar, size: 40, state: avatarState),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Finora - Assistant',
                    style: TextStyle(
                        color: AppTheme.fg(isDark), fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text('Your financial assistant',
                        style: TextStyle(color: AppTheme.muted(isDark), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          if (showChangeAvatar)
            IconButton(
              tooltip: 'Change assistant',
              icon: Icon(Icons.autorenew_rounded, color: AppTheme.muted(isDark), size: 20),
              onPressed: onChangeAvatar,
            ),
        ],
      ),
    );
  }
}

// ── SafeLock / error banners ───────────────────────────────────────────

class _SafeLockBanner extends StatelessWidget {
  final SpendingLockProvider lock;
  final bool isDark;
  const _SafeLockBanner({required this.lock, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final active = lock.isLocked || lock.isStrictLocked;
    final color = active ? AppTheme.destructive : AppTheme.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: color.withOpacity(0.12),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              active
                  ? '🔒 SafeLock Active — spending has crossed your safety threshold'
                  : '🔒 SafeLock warning ${lock.warningCount}/3',
              style: TextStyle(color: AppTheme.fg(isDark), fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String text;
  final bool isDark;
  const _ErrorBanner({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: AppTheme.warning.withOpacity(0.12),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppTheme.warning, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: AppTheme.fg(isDark), fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}

// ── Avatar orb (idle / thinking / responding animation) ───────────────

enum AiAvatarState { idle, thinking, responding }

class _AiAvatarOrb extends StatefulWidget {
  final AiAvatarOption avatar;
  final double size;
  final AiAvatarState state;
  const _AiAvatarOrb({required this.avatar, this.size = 56, this.state = AiAvatarState.idle});

  @override
  State<_AiAvatarOrb> createState() => _AiAvatarOrbState();
}

class _AiAvatarOrbState extends State<_AiAvatarOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        double scale;
        double glow;
        switch (widget.state) {
          case AiAvatarState.thinking:
            scale = 1.0 + (t * 0.07);
            glow = 14 + (t * 12);
            break;
          case AiAvatarState.responding:
            scale = 1.05;
            glow = 22;
            break;
          case AiAvatarState.idle:
            scale = 1.0 + (t * 0.035);
            glow = 8 + (t * 6);
        }
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: widget.avatar.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.avatar.gradient.last.withOpacity(0.5),
                  blurRadius: glow,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: Icon(widget.avatar.icon, color: Colors.white, size: widget.size * 0.46),
          ),
        );
      },
    );
  }
}

// ── Avatar selection ───────────────────────────────────────────────────

class _AvatarSelectionView extends StatelessWidget {
  final bool isDark;
  final ValueChanged<String> onSelect;
  const _AvatarSelectionView({required this.isDark, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Choose your AI Assistant',
            style: TextStyle(color: AppTheme.fg(isDark), fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          'Pick the character you\'d like to chat with. You can change this '
          'anytime from the chat header.',
          style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5),
        ),
        const SizedBox(height: 20),
        ...AiAvatars.all.map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => onSelect(a.id),
                child: GlassCard(
                  borderColor: a.gradient.last.withOpacity(0.35),
                  child: Row(
                    children: [
                      _AiAvatarOrb(avatar: a, size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.name,
                                style: TextStyle(
                                    color: AppTheme.fg(isDark),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(a.tagline,
                                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: AppTheme.muted(isDark)),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }
}

// ── Chat view ───────────────────────────────────────────────────────────

class _ChatView extends StatelessWidget {
  final ScrollController scrollCtrl;
  final List<ChatMessage> messages;
  final bool thinking;
  final AiAvatarOption avatar;
  final bool isDark;
  final ValueChanged<String> onQuickQuestion;
  final ValueChanged<String> onActionChip;

  static const _quickQuestions = [
    'Can I afford this?',
    'How much can I spend today?',
    'Where am I overspending?',
    'How can I save more?',
    'Show my budget',
    'Analyze my spending',
  ];

  const _ChatView({
    required this.scrollCtrl,
    required this.messages,
    required this.thinking,
    required this.avatar,
    required this.isDark,
    required this.onQuickQuestion,
    required this.onActionChip,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && !thinking) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          Center(child: _AiAvatarOrb(avatar: avatar, size: 72)),
          const SizedBox(height: 14),
          Center(
            child: Text('Hi, I\'m ${avatar.name} 👋',
                style: TextStyle(color: AppTheme.fg(isDark), fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Ask me anything about your budget, spending, or savings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: _quickQuestions
                .map((q) => _QuickQuestionChip(text: q, onTap: () => onQuickQuestion(q)))
                .toList(),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: messages.length + (thinking ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= messages.length) {
          return _ThinkingRow(avatar: avatar, isDark: isDark);
        }
        final m = messages[i];
        if (m.role == ChatRole.user) {
          return _UserBubble(message: m, isDark: isDark);
        }
        return _AiBubble(
          message: m,
          avatar: avatar,
          isDark: isDark,
          onActionChip: onActionChip,
        );
      },
    );
  }
}

class _QuickQuestionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _QuickQuestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.glass(isDark),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.secondary.withOpacity(0.35)),
        ),
        child: Text(text,
            style: TextStyle(color: AppTheme.secondary, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isDark;
  const _UserBubble({required this.message, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
  }
}

class _AiBubble extends StatelessWidget {
  final ChatMessage message;
  final AiAvatarOption avatar;
  final bool isDark;
  final ValueChanged<String> onActionChip;
  const _AiBubble({
    required this.message,
    required this.avatar,
    required this.isDark,
    required this.onActionChip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AiAvatarOrb(avatar: avatar, size: 30),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.glass(isDark),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(
                        color: message.isError
                            ? AppTheme.destructive.withOpacity(0.4)
                            : AppTheme.border(isDark)),
                  ),
                  child: Text(message.text,
                      style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13, height: 1.4)),
                ),
                if (message.suggestedActions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: message.suggestedActions
                        .map((a) => _ActionChip(text: a, onTap: () => onActionChip(a)))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _ActionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
        ),
        child: Text(text,
            style: const TextStyle(color: AppTheme.primary, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  final AiAvatarOption avatar;
  final bool isDark;
  const _ThinkingRow({required this.avatar, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AiAvatarOrb(avatar: avatar, size: 30, state: AiAvatarState.thinking),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.glass(isDark),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: AppTheme.border(isDark)),
            ),
            child: Text('AI is thinking...',
                style: TextStyle(color: AppTheme.muted(isDark), fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

// ── Input bar ───────────────────────────────────────────────────────────

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final bool enabled;
  final ValueChanged<String> onSend;

  const _ChatInputBar({
    required this.controller,
    required this.isDark,
    required this.enabled,
    required this.onSend,
  });

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold's default resizeToAvoidBottomInset already lifts this bar
    // above the keyboard, so no manual viewInsets padding is needed here.
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 10, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark).withOpacity(0.9),
        border: Border(top: BorderSide(color: AppTheme.border(isDark))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file_rounded, color: AppTheme.muted(isDark), size: 20),
            onPressed: () => _showComingSoon(context, 'Attachments'),
          ),
          IconButton(
            icon: Icon(Icons.mic_none_rounded, color: AppTheme.muted(isDark), size: 20),
            onPressed: () => _showComingSoon(context, 'Voice input'),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.glass(isDark),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.border(isDark)),
              ),
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: enabled ? onSend : null,
                style: TextStyle(color: AppTheme.fg(isDark), fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(color: AppTheme.muted(isDark), fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: enabled ? () => onSend(controller.text) : null,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.teal]),
                boxShadow: [
                  BoxShadow(
                      color: AppTheme.primary.withOpacity(enabled ? 0.45 : 0.15), blurRadius: 12),
                ],
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
            ),
          ),
        ],
      ),
    );
  }
}
