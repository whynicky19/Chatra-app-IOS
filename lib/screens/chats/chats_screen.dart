import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/chats_provider.dart';
import '../../services/api_service.dart';
import '../../services/moderation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/blocked_banner.dart';
import '../../widgets/moderation_actions.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/toast.dart';
import '../../utils/file_opener.dart';
import '../../utils/message_attachment.dart';
import '../classes/class_detail_utils.dart' show trimUrlPunctuation, fileCacheKey;

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final _searchCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  Timer? _bgPoller;
  Timer? _searchDebounce;
  late AnimationController _listAnim;
  late AnimationController _replyAnim;
  final ScrollController _chatScrollCtrl = ScrollController();
  DateTime? _lastTypingSent;
  Map<String, dynamic>? _replyTo;
  int? _scrollTrackedChatId;
  int _scrollTrackedMsgCount = 0;

  static const _avatarColors = [
    C.teal,
    Color(0xFF6366F1),
    Color(0xFFF59E0B),
    Color(0xFF0891B2),
    Color(0xFFEC4899),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFF64748B),
  ];

  late final ChatsProvider _chatsProvider = context.read<ChatsProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _replyAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    final provider = _chatsProvider;
    provider.addListener(_onProviderError);
    provider.loadSeenMsgIds().then((_) => provider.loadChats());
    _startBgPoller();
  }

  void _startBgPoller() {
    _bgPoller?.cancel();
    _bgPoller = Timer.periodic(const Duration(seconds: 10), (_) {
      _chatsProvider.pollMessages();
      _chatsProvider.refreshChatSummaries();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _bgPoller?.cancel();
      _bgPoller = null;
    } else if (state == AppLifecycleState.resumed) {
      _startBgPoller();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgPoller?.cancel();
    _searchDebounce?.cancel();
    _listAnim.dispose();
    _replyAnim.dispose();
    _chatScrollCtrl.dispose();
    _msgCtrl.dispose();
    _searchCtrl.dispose();
    _chatsProvider.removeListener(_onProviderError);
    super.dispose();
  }

  void _onProviderError() {
    final err = context.read<ChatsProvider>().errorMessage;
    if (err != null && mounted) {
      showToast(context, context.read<L10n>().t(err), error: true);
      context.read<ChatsProvider>().clearError();
    }
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScrollCtrl.hasClients) return;
      final extent = _chatScrollCtrl.position.maxScrollExtent;
      if (animated) {
        _chatScrollCtrl.animateTo(extent,
            duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      } else {
        _chatScrollCtrl.jumpTo(extent);
      }
    });
  }

  void _onMsgChanged(String _) {
    final now = DateTime.now();
    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!) > const Duration(seconds: 2)) {
      _lastTypingSent = now;
      context.read<ChatsProvider>().sendTyping();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatsProvider>();
    if (provider.activeChatId != null) return _buildChatView(provider);
    return _buildChatList(provider);
  }

  int? _chatPartnerId(ChatsProvider p, dynamic chat) {
    final myId = context.read<AuthProvider>().userId;
    final parts = p.chatUsers[chat['id']] ?? [];
    for (final u in parts) {
      final id = (u['id'] as num?)?.toInt();
      if (id != null && id != myId) return id;
    }
    return null;
  }

  String? _userName(int userId) {
    final provider = context.read<ChatsProvider>();
    for (final parts in provider.chatUsers.values) {
      for (final u in parts) {
        if ((u['id'] as num?)?.toInt() == userId) {
          return (u['full_name'] ?? u['email']?.toString().split('@').first)
              ?.toString();
        }
      }
    }
    return null;
  }

  Widget _buildChatList(ChatsProvider provider) {
    final l = context.watch<L10n>();
    final mod = context.watch<ModerationService>();
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sorted = provider.sortedChats;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 0), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('messages_title'), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: adaptiveText1(context), letterSpacing: -0.4)),
            Text(l.t('your_conversations'), style: const TextStyle(fontSize: 13, color: C.text4)),
          ])),
        ])),
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(
          height: 38,
          decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Padding(padding: EdgeInsets.only(left: 10),
              child: Icon(CupertinoIcons.search, size: 16, color: C.text4)),
            const SizedBox(width: 6),
            Expanded(child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: l.t('search_chats'),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintStyle: const TextStyle(color: C.text4, fontSize: 15),
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: (q) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                  context.read<ChatsProvider>().searchUsers(q);
                });
              },
            )),
          ]),
        )),
        if (provider.searchResults.isNotEmpty) Container(
          constraints: const BoxConstraints(maxHeight: 220),
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12)]),
          child: ClipRRect(borderRadius: BorderRadius.circular(16), child: ListView(shrinkWrap: true,
            children: provider.searchResults
              .where((u) => !mod.isBlocked((u['id'] as num?)?.toInt()))
              .map((u) {
              final color = _avatarColors[(u['id'] ?? 0) % _avatarColors.length];
              final initials = (u['full_name'] ?? u['email'] ?? '?')[0].toUpperCase();
              return ListTile(
                leading: CircleAvatar(radius: 22, backgroundColor: color.withValues(alpha: 0.15),
                  child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16))),
                title: Text(u['full_name'] ?? u['email']?.split('@').first ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: Text(u['email'] ?? '', style: const TextStyle(fontSize: 12, color: C.text4)),
                onTap: () async {
                  await context.read<ChatsProvider>().openDM(u);
                  if (!mounted) return;
                  _searchCtrl.clear();
                },
              );
            }).toList()))),
        const SizedBox(height: 8),
        Expanded(child: RefreshIndicator(
          onRefresh: () => context.read<ChatsProvider>().loadChats(),
          child: provider.loading
          ? ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              itemCount: 6,
              itemBuilder: (_, i) => TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 200 + i * 60),
                curve: Curves.easeOut,
                builder: (_, t, child) => Opacity(opacity: t, child: child),
                child: const SkeletonChatRow(),
              ),
            )
          : sorted.isEmpty
            ? _emptyState()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: sorted.length,
                itemBuilder: (ctx, i) {
                  final c = sorted[i]; final id = c['id'] as int;
                  final color = _avatarColors[id % _avatarColors.length];
                  final title = provider.chatTitle(c);
                  final blocked = mod.isBlocked(_chatPartnerId(provider, c));
                  final unreadN = blocked ? 0 : provider.unreadCount(id);
                  final unread = unreadN > 0;
                  final time = l.t(provider.chatTime(id));
                  final preview = blocked
                      ? l.t('you_blocked_user')
                      : l.t(provider.lastPreview(id) ?? 'no_messages');
                  final initials = title.isNotEmpty ? title[0].toUpperCase() : '?';

                  return TweenAnimationBuilder<double>(
                    key: ValueKey(id),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 320 + i * 65),
                    curve: Curves.easeOutCubic,
                    builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 22 * (1 - t)), child: child)),
                    child: Dismissible(
                      key: ValueKey('dismiss_$id'),
                      direction: DismissDirection.endToStart,
                      dismissThresholds: const {DismissDirection.endToStart: 0.4},
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(AppRadii.card),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(CupertinoIcons.trash, color: Colors.white, size: 24),
                          const SizedBox(height: 4),
                          Text(l.t('delete'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      confirmDismiss: (_) async {
                        HapticFeedback.mediumImpact();
                        return await showConfirmDialog(context,
                          title: l.t('delete_chat_q'),
                          message: l.t('delete_chat_msg'),
                          icon: CupertinoIcons.trash,
                          danger: true,
                          confirmText: l.t('delete'),
                          cancelText: l.t('cancel')) ?? false;
                      },
                      onDismissed: (_) async {
                        final ok = await context.read<ChatsProvider>().deleteChat(id);
                        if (!ok && mounted) showToast(context, l.t('delete_error'), error: true);
                      },
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.read<ChatsProvider>().markSeen(id);
                          context.read<ChatsProvider>().setActiveChatId(id);
                          _scrollToBottom();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(AppRadii.card),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                          ),
                          child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                            Stack(clipBehavior: Clip.none, children: [
                              Container(width: 52, height: 52,
                                decoration: BoxDecoration(gradient: RadialGradient(colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.12)]), shape: BoxShape.circle),
                                child: Center(child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20)))),
                              if (unread) Positioned(right: -4, top: -4,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                  padding: const EdgeInsets.symmetric(horizontal: 5),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: surface, width: 2),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    unreadN > 99 ? '99+' : '$unreadN',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                                  ),
                                )),
                            ]),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: unread ? FontWeight.w800 : FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                if (time.isNotEmpty) Text(time, style: TextStyle(fontSize: 11, color: unread ? Theme.of(context).colorScheme.primary : C.text4, fontWeight: unread ? FontWeight.w700 : FontWeight.w400)),
                              ]),
                              const SizedBox(height: 4),
                              Row(children: [
                                Expanded(child: Text(preview, style: TextStyle(fontSize: 13, color: unread ? adaptiveText1(context) : C.text4, fontWeight: unread ? FontWeight.w500 : FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                if (unread) Container(width: 8, height: 8, margin: const EdgeInsets.only(left: 8), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle)),
                              ]),
                            ])),
                          ])),
                        ),
                      ),
                    ),
                  );
                }))),
      ])),
    );
  }

  Widget _emptyState() {
    final l = context.read<L10n>();
    // AlwaysScrollableScrollPhysics обязателен: без него pull-to-refresh мёртв на пустом списке.
    return Center(child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(CupertinoIcons.bubble_left, size: 36, color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 16),
      Text(l.t('no_chats'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
      const SizedBox(height: 6),
      Text(l.t('search_above'), style: const TextStyle(fontSize: 14, color: C.text4)),
    ])));
  }

  Widget _buildChatView(ChatsProvider provider) {
    final l = context.watch<L10n>();
    final mod = context.watch<ModerationService>();
    final allMsgs = provider.messages[provider.activeChatId] ?? [];
    final chat = provider.chats.firstWhere((c) => c['id'] == provider.activeChatId, orElse: () => {'name': 'Chat'});
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = provider.chatTitle(chat);
    final color = _avatarColors[(provider.activeChatId ?? 0) % _avatarColors.length];

    final participants = provider.chatUsers[provider.activeChatId] ?? [];
    int? partnerId = participants
        .where((u) => (u['id'] as num?)?.toInt() != auth.userId)
        .map((u) => (u['id'] as num?)?.toInt())
        .firstWhere((id) => id != null, orElse: () => null);
    partnerId ??= allMsgs
        .map((m) => (m['user_id'] as num?)?.toInt())
        .firstWhere((id) => id != null && id != auth.userId, orElse: () => null);
    final partnerBlocked = mod.isBlocked(partnerId);

    final msgs = mod.blockedIds.isEmpty
        ? allMsgs
        : allMsgs.where((m) => !mod.isBlocked((m['user_id'] as num?)?.toInt())).toList();

    // Автоскролл вниз при новом сообщении (как в чате с ИИ) — WS/поллинг
    // добавляют сообщения через провайдер, а не через _send(), поэтому сам
    // экран должен заметить прирост списка и докрутить.
    final activeChatId = provider.activeChatId;
    if (activeChatId != null) {
      if (_scrollTrackedChatId != activeChatId) {
        _scrollTrackedChatId = activeChatId;
        _scrollTrackedMsgCount = msgs.length;
      } else if (msgs.length > _scrollTrackedMsgCount) {
        _scrollTrackedMsgCount = msgs.length;
        _scrollToBottom(animated: true);
      } else {
        _scrollTrackedMsgCount = msgs.length;
      }
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05), blurRadius: 8)],
          ),
          child: SafeArea(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_left, size: 18),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final p = context.read<ChatsProvider>();
                  if (p.activeChatId != null) p.markSeen(p.activeChatId!);
                  p.setActiveChatId(null);
                }),
              Container(width: 38, height: 38,
                decoration: BoxDecoration(gradient: RadialGradient(colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.12)]), shape: BoxShape.circle),
                child: Center(child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)))),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                  if (provider.someoneIsTyping)
                    Text(context.read<L10n>().t('typing_indicator'), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
                ],
              )),
              if (partnerId != null)
                IconButton(
                  icon: const Icon(CupertinoIcons.ellipsis, size: 20),
                  onPressed: () => _showChatModerationMenu(partnerId!, partnerBlocked),
                ),
            ]),
          )),
        ),
      ),
      body: Column(children: [
        Expanded(child: msgs.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(CupertinoIcons.smiley, size: 48, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(l.t('start_dialog'), style: const TextStyle(fontSize: 16, color: C.text4, fontWeight: FontWeight.w500)),
            ]))
          : ListView.builder(
              controller: _chatScrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              itemCount: msgs.length,
              itemBuilder: (ctx, i) {
                final m = msgs[i]; final isMe = m['user_id'] == auth.userId;
                final showTime = i == msgs.length - 1 || (msgs[i + 1]['user_id'] != m['user_id']);
                return TweenAnimationBuilder<double>(
                  key: ValueKey('msg_${m['id'] ?? i}'),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (_, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                        offset: Offset(isMe ? 18 * (1 - t) : -18 * (1 - t), 8 * (1 - t)),
                        child: child)),
                  child: _SwipeableMessage(
                    key: ValueKey('msg_${m['id']}'),
                    isMe: isMe,
                    onReply: () => setState(() {
                      _replyTo = m;
                      _replyAnim.forward(from: 0);
                    }),
                    child: Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _showMessageActions(m, isMe),
                        child: Container(
                        margin: EdgeInsets.only(bottom: showTime ? 12 : 3),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        decoration: BoxDecoration(
                          gradient: isMe ? LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                          color: isMe ? null : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMe ? 20 : 6),
                            bottomRight: Radius.circular(isMe ? 6 : 20)),
                          boxShadow: [BoxShadow(
                            color: isMe ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25) : Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
                            blurRadius: 12, offset: const Offset(0, 3))],
                        ),
                        child: _buildMessageContent(m['content'] ?? '', isMe),
                      ),
                      ),
                    ),
                  ),
                );
              })),

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => SizeTransition(
            sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: provider.someoneIsTyping
              ? const _TypingBubble(key: ValueKey('typing'))
              : const SizedBox.shrink(key: ValueKey('no_typing')),
        ),

        if (_replyTo != null) _ReplyPreview(
          message: _replyTo!,
          animation: _replyAnim,
          onCancel: () => setState(() { _replyTo = null; }),
        ),

        if (partnerBlocked)
          BlockedBanner(onUnblock: () => unblockUser(context, userId: partnerId!))
        else
          _ChatInputBar(
            ctrl: _msgCtrl,
            onSend: _send,
            onAdd: provider.uploading ? null : () => _showPhotoMenu(context, provider.activeChatId!),
            onChanged: _onMsgChanged,
            uploading: provider.uploading,
          ),
      ]),
    );
  }

  void _showChatModerationMenu(int partnerId, bool blocked) {
    final l = context.read<L10n>();
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: adaptiveBorder(ctx), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 10),
          _modTile(ctx, CupertinoIcons.exclamationmark_octagon, l.t('report_user'), C.red, () {
            Navigator.pop(ctx);
            showReportSheet(context, reportedUserId: partnerId, userName: _userName(partnerId));
          }),
          if (blocked)
            _modTile(ctx, CupertinoIcons.lock_open, l.t('unblock_user_action'), Theme.of(ctx).colorScheme.primary, () {
              Navigator.pop(ctx);
              unblockUser(context, userId: partnerId);
            })
          else
            _modTile(ctx, CupertinoIcons.nosign, l.t('block_user_action'), C.red, () {
              Navigator.pop(ctx);
              confirmAndBlock(context, userId: partnerId, userName: _userName(partnerId));
            }),
        ]),
      )),
    );
  }

  void _showMessageActions(Map<String, dynamic> m, bool isMe) {
    final l = context.read<L10n>();
    final content = (m['content'] ?? '').toString();
    final senderId = (m['user_id'] as num?)?.toInt();
    final messageId = (m['id'] as num?)?.toInt();
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: adaptiveBorder(ctx), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 10),
          _modTile(ctx, CupertinoIcons.doc_on_clipboard, l.t('copy_action'), adaptiveText1(ctx), () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: content));
            showToast(context, l.t('copied'));
          }),
          _modTile(ctx, CupertinoIcons.arrowshape_turn_up_left, l.t('reply_to'), adaptiveText1(ctx), () {
            Navigator.pop(ctx);
            setState(() { _replyTo = m; _replyAnim.forward(from: 0); });
          }),
          if (!isMe && senderId != null) ...[
            _modTile(ctx, CupertinoIcons.exclamationmark_octagon, l.t('report_message'), C.red, () {
              Navigator.pop(ctx);
              showReportSheet(context, reportedUserId: senderId, userName: _userName(senderId), content: content, messageId: messageId);
            }),
            _modTile(ctx, CupertinoIcons.nosign, l.t('block_user_action'), C.red, () {
              Navigator.pop(ctx);
              confirmAndBlock(context, userId: senderId, userName: _userName(senderId));
            }),
          ],
        ]),
      )),
    );
  }

  Widget _modTile(BuildContext ctx, IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }

  void _send() async {
    if (_msgCtrl.text.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    String content = _msgCtrl.text.trim();
    if (_replyTo != null) {
      final senderName = _replyTo!['sender_name'] ?? _replyTo!['user_name'] ?? 'User';
      // В цитату кладём подпись, а не подписанную ссылку на файл.
      final replyText = messagePreviewText((_replyTo!['content'] ?? '').toString());
      content = '> $senderName: $replyText\n\n$content';
      setState(() => _replyTo = null);
    }
    _msgCtrl.clear();
    await context.read<ChatsProvider>().sendMessage(content);
    if (!mounted) return;
    _scrollToBottom(animated: true);
  }

  void _showPhotoMenu(BuildContext context, int chatId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: C.text4.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          _photoOption(ctx, CupertinoIcons.photo, context.read<L10n>().t('gallery'), () async {
            Navigator.pop(ctx);
            final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
            if (!mounted) return;
            if (img != null) await _uploadAndSend(chatId, img);
          }),
          const SizedBox(height: 8),
          _photoOption(ctx, CupertinoIcons.camera, context.read<L10n>().t('camera'), () async {
            Navigator.pop(ctx);
            final img = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1200, imageQuality: 85);
            if (!mounted) return;
            if (img != null) await _uploadAndSend(chatId, img);
          }),
        ]),
      )),
    );
  }

  Widget _photoOption(BuildContext ctx, IconData icon, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: adaptiveSurface2(ctx), borderRadius: BorderRadius.circular(AppRadii.tile)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 14),
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const Spacer(),
        const Icon(CupertinoIcons.chevron_right, size: 18, color: C.text4),
      ]),
    ),
  );

  Future<void> _uploadAndSend(int chatId, XFile img) async {
    final err = await context.read<ChatsProvider>().uploadAndSend(chatId, img.path, img.name);
    if (!mounted) return;
    if (err != null) showToast(context, context.read<L10n>().t(err), error: true);
  }

  // Разбор содержимого сообщения (regex вложений/ссылок) дорогой и вызывается
  // на каждый rebuild списка (поллинг, тайпинг-индикатор) — кэшируем по
  // тексту сообщения, он неизменяем после отправки.
  final Map<String, String> _fixedContentCache = {};
  final Map<String, MessageAttachment?> _attachmentCache = {};

  Widget _buildMessageContent(String content, bool isMe) {
    if (content.startsWith('> ')) {
      final nlIdx = content.indexOf('\n\n');
      if (nlIdx > 0) {
        final quoteLine = content.substring(2, nlIdx);
        final mainText = content.substring(nlIdx + 2).trim();
        final colonIdx = quoteLine.indexOf(': ');
        final senderName = colonIdx > 0 ? quoteLine.substring(0, colonIdx) : '';
        final quoteText = colonIdx > 0 ? quoteLine.substring(colonIdx + 2) : quoteLine;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withValues(alpha: 0.18) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (senderName.isNotEmpty)
                  Text(senderName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                Text(quoteText, style: const TextStyle(fontSize: 12, color: C.text3),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(height: 6),
            Text(mainText, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : null, height: 1.4)),
          ]),
        );
      }
    }
    final fixedContent = _fixedContentCache.putIfAbsent(content, () {
      try {
        return context.read<ApiService>().fixUrlsInText(content);
      } catch (_) {
        return content;
      }
    });

    // Вложение (сайт шлёт markdown `[Фото](url) — имя`, приложение — голую
    // ссылку). Разбираем общим парсером: раньше из markdown в URL уезжала
    // закрывающая скобка и картинка не грузилась.
    final att = _attachmentCache.putIfAbsent(content, () => parseMessageAttachment(fixedContent));
    if (att != null) {
      final url = context.read<ApiService>().fixUrl(att.url);
      if (att.isImage) {
        return ClipRRect(borderRadius: BorderRadius.circular(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => openRemoteFile(context, context.read<ApiService>(), url, att.name),
            child: CachedNetworkImage(
              imageUrl: url,
              cacheKey: fileCacheKey(url),
              memCacheWidth: 800,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 200,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, __) => Container(height: 200, color: adaptiveSurface2(context), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary))),
              errorWidget: (_, __, ___) => Container(height: 80, padding: const EdgeInsets.all(16), child: Row(children: [
                const Icon(CupertinoIcons.photo, color: C.text4), const SizedBox(width: 8),
                Flexible(child: Text(att.name, style: TextStyle(color: isMe ? Colors.white70 : C.text4, fontSize: 12))),
              ])),
            ),
          ),
          if (att.caption.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Text(att.caption, style: TextStyle(fontSize: 14, color: isMe ? Colors.white : null))),
        ]));
      }
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => openRemoteFile(context, context.read<ApiService>(), url, att.name),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isMe ? Colors.white : Theme.of(context).colorScheme.primary).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.doc_fill, size: 18, color: isMe ? Colors.white70 : Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(child: Text(att.name, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: isMe ? Colors.white : Theme.of(context).colorScheme.primary))),
              ]),
            ),
          ),
          if (att.caption.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
            child: Text(att.caption, style: TextStyle(fontSize: 14, color: isMe ? Colors.white : null))),
        ]));
    }

    final urlRegex = RegExp(r'https?://\S+');
    final urlMatch = urlRegex.firstMatch(fixedContent);
    if (urlMatch != null) {
      // \S+ цепляет точку/скобку из речи — без тримминга ломается подпись ссылки.
      final url = trimUrlPunctuation(urlMatch.group(0)!);
      final before = fixedContent.substring(0, urlMatch.start).trim();
      final after = fixedContent.substring(urlMatch.start + url.length).trim();
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (before.isNotEmpty) Text(before, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : null)),
        Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: (isMe ? Colors.white : Theme.of(context).colorScheme.primary).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(CupertinoIcons.link, size: 16, color: isMe ? Colors.white70 : Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(child: Text(url.length > 40 ? '${url.substring(0, 40)}...' : url,
              style: TextStyle(fontSize: 12, color: isMe ? Colors.white70 : Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline))),
          ])),
        if (after.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
          child: Text(after, style: TextStyle(fontSize: 14, color: isMe ? Colors.white70 : C.text4))),
      ]));
    }

    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(fixedContent, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : null, height: 1.4)));
  }
}

class _ChatInputBar extends StatefulWidget {
  final TextEditingController ctrl;
  final VoidCallback onSend;
  final VoidCallback? onAdd;
  final ValueChanged<String> onChanged;
  final bool uploading;

  const _ChatInputBar({
    required this.ctrl,
    required this.onSend,
    required this.onAdd,
    required this.onChanged,
    this.uploading = false,
  });

  @override
  State<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<_ChatInputBar> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(_ChatInputBar old) {
    super.didUpdateWidget(old);
    if (old.ctrl != widget.ctrl) {
      old.ctrl.removeListener(_rebuild);
      widget.ctrl.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l = context.read<L10n>();
    final hasText = widget.ctrl.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, bottomBarInset(context)),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
          blurRadius: 12, offset: const Offset(0, -2),
        )],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        GestureDetector(
          onTap: widget.onAdd,
          child: Container(
            width: 40, height: 40,
            margin: const EdgeInsets.only(right: 6, bottom: 3),
            decoration: BoxDecoration(
              color: adaptiveSurface2(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(CupertinoIcons.plus, size: 22, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 46),
            decoration: BoxDecoration(
              color: adaptiveSurface2(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hasText ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: TextField(
              controller: widget.ctrl,
              decoration: InputDecoration(
                hintText: l.t('message'),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              ),
              onChanged: widget.onChanged,
              onSubmitted: (_) => widget.onSend(),
              maxLines: 4, minLines: 1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: widget.onSend,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: hasText
                    ? [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]
                    : [Theme.of(context).colorScheme.primary.withValues(alpha: 0.55), Theme.of(context).colorScheme.secondary.withValues(alpha: 0.45)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: hasText
                  ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.38), blurRadius: 14, offset: const Offset(0, 4))]
                  : null,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                hasText ? CupertinoIcons.paperplane_fill : CupertinoIcons.paperplane_fill,
                key: ValueKey(hasText),
                color: Colors.white, size: 20,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble({super.key});
  @override State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20), topRight: Radius.circular(20),
              bottomLeft: Radius.circular(6), bottomRight: Radius.circular(20)),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
              blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_ctrl.value - i / 3.0) % 1.0;
                final brightness = (sin(phase * 2 * pi) + 1) / 2;
                return Container(
                  width: 7, height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3 + 0.7 * brightness),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeableMessage extends StatefulWidget {
  final Widget child;
  final bool isMe;
  final VoidCallback onReply;

  const _SwipeableMessage({
    super.key,
    required this.child,
    required this.isMe,
    required this.onReply,
  });

  @override
  State<_SwipeableMessage> createState() => _SwipeableMessageState();
}

class _SwipeableMessageState extends State<_SwipeableMessage>
    with SingleTickerProviderStateMixin {
  double _dx = 0;
  bool _hapticFired = false;
  late AnimationController _springCtrl;
  late Animation<double> _springAnim;

  @override
  void initState() {
    super.initState();
    _springCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _springAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _springCtrl, curve: Curves.elasticOut),
    );
    _springCtrl.addListener(() => setState(() => _dx = _springAnim.value));
  }

  @override
  void dispose() {
    _springCtrl.dispose();
    super.dispose();
  }

  double _applyResistance(double raw) {
    if (raw <= 40) return raw;
    return 40 + (raw - 40) / 2.5;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.delta.dx;
    final newRaw = (_dx + delta).clamp(0.0, 120.0);
    setState(() => _dx = _applyResistance(newRaw));

    if (_dx > 60 && !_hapticFired) {
      _hapticFired = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails _) {
    if (_dx > 60) {
      widget.onReply();
    }
    _springAnim = Tween<double>(begin: _dx, end: 0).animate(
      CurvedAnimation(parent: _springCtrl, curve: Curves.elasticOut),
    );
    _springCtrl.forward(from: 0);
    _hapticFired = false;
    setState(() => _dx = 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(children: [
        if (_dx > 40)
          Positioned(
            left: 8,
            top: 0, bottom: 0,
            child: Align(
              alignment: Alignment.center,
              child: AnimatedScale(
                scale: ((_dx - 40) / 20).clamp(0.0, 1.0),
                duration: Duration.zero,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(CupertinoIcons.arrowshape_turn_up_left, size: 18, color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          ),
        Transform.translate(
          offset: Offset(_dx, 0),
          child: widget.child,
        ),
      ]),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final Map<String, dynamic> message;
  final AnimationController animation;
  final VoidCallback onCancel;

  const _ReplyPreview({
    required this.message,
    required this.animation,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final senderName = message['sender_name'] ?? message['user_name'] ?? 'User';
    final text = messagePreviewText((message['content'] ?? '').toString());
    final surface = Theme.of(context).colorScheme.surface;

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: FadeTransition(
        opacity: animation,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          decoration: BoxDecoration(
            color: surface,
            border: Border(
              top: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2), width: 1),
            ),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
              blurRadius: 6, offset: const Offset(0, -2),
            )],
          ),
          child: Row(children: [
            Container(width: 3, height: 40, decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(senderName, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary,
              )),
              Text(text, style: const TextStyle(fontSize: 13, color: C.text3),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            GestureDetector(
              onTap: onCancel,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: adaptiveSurface2(context),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.xmark, size: 12, color: C.text4),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
