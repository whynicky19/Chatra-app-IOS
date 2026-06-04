import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/chats_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/toast.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  // Background timer: refreshes unread badges for the chat list.
  // Runs at 10 s; WS handles the open-chat stream in real time.
  Timer? _bgPoller;
  late AnimationController _listAnim;
  late AnimationController _replyAnim;
  final ScrollController _chatScrollCtrl = ScrollController();
  // Throttle: send typing event at most once per 2 s.
  DateTime? _lastTypingSent;
  // Reply state
  Map<String, dynamic>? _replyTo;

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

  @override
  void initState() {
    super.initState();
    _listAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _replyAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    final provider = context.read<ChatsProvider>();
    provider.addListener(_onProviderError);
    provider.loadSeenMsgIds().then((_) => provider.loadChats());
    // Background poll for unread counts while browsing the chat list.
    // Skips the WS-active chat automatically inside pollMessages().
    _bgPoller = Timer.periodic(const Duration(seconds: 10), (_) {
      context.read<ChatsProvider>().pollMessages();
    });
  }

  @override
  void dispose() {
    _bgPoller?.cancel();
    _listAnim.dispose();
    _replyAnim.dispose();
    _chatScrollCtrl.dispose();
    _msgCtrl.dispose();
    _searchCtrl.dispose();
    context.read<ChatsProvider>().removeListener(_onProviderError);
    super.dispose();
  }

  void _onProviderError() {
    final err = context.read<ChatsProvider>().errorMessage;
    if (err != null && mounted) {
      showToast(context, err, error: true);
      context.read<ChatsProvider>().clearError();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
      }
    });
  }

  // Throttled: sends a typing WS event at most once every 2 s.
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

  // ── Chat list ─────────────────────────────────────────────────────────────────

  Widget _buildChatList(ChatsProvider provider) {
    final l = context.watch<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 0), child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('messages_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: C.teal)),
            Text(l.t('your_conversations'), style: const TextStyle(fontSize: 13, color: C.text4)),
          ]),
          const Spacer(),
          GestureDetector(
            onTap: () { FocusScope.of(context).requestFocus(FocusNode()); showToast(context, l.t('find_user_hint')); },
            child: Container(width: 44, height: 44, decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.edit_outlined, color: Colors.white, size: 20))),
        ])),
        const SizedBox(height: 16),
        // Search bar
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Найти или начать диалог...',
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: C.text4),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.symmetric(vertical: 14)),
            onChanged: (q) => context.read<ChatsProvider>().searchUsers(q),
          ))),
        // Search results
        if (provider.searchResults.isNotEmpty) Container(
          constraints: const BoxConstraints(maxHeight: 220),
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12)]),
          child: ClipRRect(borderRadius: BorderRadius.circular(16), child: ListView(shrinkWrap: true,
            children: provider.searchResults.map((u) {
              final color = _avatarColors[(u['id'] ?? 0) % _avatarColors.length];
              final initials = (u['full_name'] ?? u['email'] ?? '?')[0].toUpperCase();
              return ListTile(
                leading: CircleAvatar(radius: 22, backgroundColor: color.withOpacity(0.15),
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
        // Chat list
        Expanded(child: provider.loading
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
          : provider.chats.isEmpty
            ? _emptyState()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: provider.sortedChats.length,
                itemBuilder: (ctx, i) {
                  final c = provider.sortedChats[i]; final id = c['id'] as int;
                  final color = _avatarColors[id % _avatarColors.length];
                  final title = provider.chatTitle(c);
                  final unread = provider.hasUnread(id);
                  final time = provider.chatTime(id);
                  final preview = provider.lastPreview(id);
                  final initials = title.isNotEmpty ? title[0].toUpperCase() : '?';

                  return TweenAnimationBuilder<double>(
                    key: ValueKey(id),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 320 + i * 65),
                    curve: Curves.easeOutCubic,
                    builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 22 * (1 - t)), child: child)),
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
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                          Stack(children: [
                            Container(width: 52, height: 52,
                              decoration: BoxDecoration(gradient: RadialGradient(colors: [color.withOpacity(0.3), color.withOpacity(0.12)]), shape: BoxShape.circle),
                              child: Center(child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20)))),
                            if (unread) Positioned(right: 0, bottom: 0,
                              child: Container(width: 14, height: 14,
                                decoration: BoxDecoration(color: C.teal, shape: BoxShape.circle, border: Border.all(color: surface, width: 2)))),
                          ]),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: unread ? FontWeight.w800 : FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              if (time.isNotEmpty) Text(time, style: TextStyle(fontSize: 11, color: unread ? C.teal : C.text4, fontWeight: unread ? FontWeight.w700 : FontWeight.w400)),
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              Expanded(child: Text(preview, style: TextStyle(fontSize: 13, color: unread ? adaptiveText1(context) : C.text4, fontWeight: unread ? FontWeight.w500 : FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              if (unread) Container(width: 8, height: 8, margin: const EdgeInsets.only(left: 8), decoration: const BoxDecoration(color: C.teal, shape: BoxShape.circle)),
                            ]),
                          ])),
                        ])),
                      ),
                    ),
                  );
                })),
      ])),
    );
  }

  Widget _emptyState() {
    final l = context.read<L10n>();
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: C.teal.withOpacity(0.1), shape: BoxShape.circle),
        child: const Icon(Icons.chat_bubble_outline_rounded, size: 36, color: C.teal)),
      const SizedBox(height: 16),
      Text(l.t('no_chats'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
      const SizedBox(height: 6),
      Text(l.t('search_above'), style: const TextStyle(fontSize: 14, color: C.text4)),
    ]));
  }

  // ── Chat view ─────────────────────────────────────────────────────────────────

  Widget _buildChatView(ChatsProvider provider) {
    final l = context.watch<L10n>();
    final msgs = provider.messages[provider.activeChatId] ?? [];
    final chat = provider.chats.firstWhere((c) => c['id'] == provider.activeChatId, orElse: () => {'name': 'Chat'});
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = provider.chatTitle(chat);
    final color = _avatarColors[(provider.activeChatId ?? 0) % _avatarColors.length];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 8)],
          ),
          child: SafeArea(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final p = context.read<ChatsProvider>();
                  if (p.activeChatId != null) p.markSeen(p.activeChatId!);
                  p.setActiveChatId(null);
                }),
              Container(width: 38, height: 38,
                decoration: BoxDecoration(gradient: RadialGradient(colors: [color.withOpacity(0.3), color.withOpacity(0.12)]), shape: BoxShape.circle),
                child: Center(child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)))),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                  // Typing sub-label in the app bar
                  if (provider.someoneIsTyping)
                    Text(context.read<L10n>().t('typing_indicator'), style: const TextStyle(fontSize: 11, color: C.teal, fontWeight: FontWeight.w500)),
                ],
              )),
            ]),
          )),
        ),
      ),
      body: Column(children: [
        // Message list
        Expanded(child: msgs.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.waving_hand_outlined, size: 48, color: C.teal.withOpacity(0.4)),
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
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 200),
                  builder: (_, t, child) => Opacity(opacity: t,
                    child: Transform.translate(offset: Offset(isMe ? 20 * (1 - t) : -20 * (1 - t), 0), child: child)),
                  child: _SwipeableMessage(
                    key: ValueKey('msg_${m['id']}'),
                    isMe: isMe,
                    onReply: () => setState(() {
                      _replyTo = m;
                      _replyAnim.forward(from: 0);
                    }),
                    child: Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: EdgeInsets.only(bottom: showTime ? 12 : 3),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        decoration: BoxDecoration(
                          gradient: isMe ? const LinearGradient(colors: [C.teal, C.tealDk], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                          color: isMe ? null : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMe ? 20 : 6),
                            bottomRight: Radius.circular(isMe ? 6 : 20)),
                          boxShadow: [BoxShadow(
                            color: isMe ? C.teal.withOpacity(0.25) : Colors.black.withOpacity(isDark ? 0.2 : 0.08),
                            blurRadius: 12, offset: const Offset(0, 3))],
                        ),
                        child: _buildMessageContent(m['content'] ?? '', isMe),
                      ),
                    ),
                  ),
                );
              })),

        // Typing indicator bubble
        if (provider.someoneIsTyping) const _TypingBubble(),

        // Reply preview
        if (_replyTo != null) _ReplyPreview(
          message: _replyTo!,
          animation: _replyAnim,
          onCancel: () => setState(() { _replyTo = null; }),
        ),

        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.06), blurRadius: 12, offset: const Offset(0, -2))],
          ),
          child: Row(children: [
            GestureDetector(
              onTap: () => _showPhotoMenu(context, provider.activeChatId!),
              child: Container(width: 40, height: 40, margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.add_rounded, size: 22, color: C.teal))),
            Expanded(child: Container(
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(24)),
              child: TextField(
                controller: _msgCtrl,
                decoration: InputDecoration(
                  hintText: l.t('message'),
                  border: InputBorder.none, enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none, filled: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                onChanged: _onMsgChanged,
                onSubmitted: (_) => _send(),
                maxLines: 4, minLines: 1,
              ))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.9, end: 1.0),
                duration: const Duration(milliseconds: 150),
                builder: (_, t, child) => Transform.scale(scale: t, child: child),
                child: Container(width: 48, height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [C.teal, C.tealDk], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: C.teal.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
              )),
          ]),
        ),
      ]),
    );
  }

  void _send() async {
    if (_msgCtrl.text.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    String content = _msgCtrl.text.trim();
    if (_replyTo != null) {
      final senderName = _replyTo!['sender_name'] ?? _replyTo!['user_name'] ?? 'User';
      final replyText = _replyTo!['content'] ?? '';
      content = '> $senderName: $replyText\n\n$content';
      setState(() => _replyTo = null);
    }
    _msgCtrl.clear();
    await context.read<ChatsProvider>().sendMessage(content);
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Photo menu ────────────────────────────────────────────────────────────────

  void _showPhotoMenu(BuildContext context, int chatId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: C.text4.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          _photoOption(ctx, Icons.photo_library_rounded, context.read<L10n>().t('gallery'), () async {
            Navigator.pop(ctx);
            final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
            if (!mounted) return;
            if (img != null) await _uploadAndSend(chatId, img);
          }),
          const SizedBox(height: 8),
          _photoOption(ctx, Icons.camera_alt_rounded, context.read<L10n>().t('camera'), () async {
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
      decoration: BoxDecoration(color: adaptiveSurface2(ctx), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: C.teal)),
        const SizedBox(width: 14),
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const Spacer(),
        const Icon(Icons.chevron_right, size: 20, color: C.text4),
      ]),
    ),
  );

  Future<void> _uploadAndSend(int chatId, XFile img) async {
    final err = await context.read<ChatsProvider>().uploadAndSend(chatId, img.path, img.name);
    if (!mounted) return;
    if (err != null) showToast(context, err, error: true);
  }

  // ── Message content renderer ──────────────────────────────────────────────────

  Widget _buildMessageContent(String content, bool isMe) {
    // Parse quote prefix "> sender: text\n\nmain"
    if (content.startsWith('> ')) {
      final nlIdx = content.indexOf('\n\n');
      if (nlIdx > 0) {
        final quoteLine = content.substring(2, nlIdx); // "sender: text"
        final mainText = content.substring(nlIdx + 2).trim();
        final colonIdx = quoteLine.indexOf(': ');
        final senderName = colonIdx > 0 ? quoteLine.substring(0, colonIdx) : '';
        final quoteText = colonIdx > 0 ? quoteLine.substring(colonIdx + 2) : quoteLine;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Quote block
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.18) : C.tealLt.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: C.teal, width: 3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (senderName.isNotEmpty)
                  Text(senderName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal)),
                Text(quoteText, style: const TextStyle(fontSize: 12, color: C.text3),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(height: 6),
            // Main text
            Text(mainText, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : null, height: 1.4)),
          ]),
        );
      }
    }
    // Fall through to original renderer
    String fixedContent = content;
    try {
      final api = context.read<ApiService>();
      fixedContent = content
          .replaceAll(RegExp(r'https?://localhost:\d+'), api.baseUrl)
          .replaceAll(RegExp(r'https?://127\.0\.0\.1:\d+'), api.baseUrl);
    } catch (_) {}

    final imgRegex = RegExp(r'https?://\S+\.(jpg|jpeg|png|gif|webp)', caseSensitive: false);
    final imgMatch = imgRegex.firstMatch(fixedContent);
    if (imgMatch != null) {
      final url = imgMatch.group(0)!;
      final textPart = fixedContent.replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '').replaceAll(url, '').trim();
      return ClipRRect(borderRadius: BorderRadius.circular(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Image.network(url, fit: BoxFit.cover, width: double.infinity, height: 200,
          loadingBuilder: (_, child, progress) => progress == null ? child
              : Container(height: 200, color: adaptiveSurface2(context), child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.teal))),
          errorBuilder: (_, __, ___) => Container(height: 80, padding: const EdgeInsets.all(16), child: Row(children: [
            const Icon(Icons.broken_image, color: C.text4), const SizedBox(width: 8),
            Flexible(child: Text(url.split('/').last, style: TextStyle(color: isMe ? Colors.white70 : C.text4, fontSize: 12))),
          ]))),
        if (textPart.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Text(textPart, style: TextStyle(fontSize: 14, color: isMe ? Colors.white : null))),
      ]));
    }

    final urlRegex = RegExp(r'https?://\S+');
    final urlMatch = urlRegex.firstMatch(fixedContent);
    if (urlMatch != null) {
      final url = urlMatch.group(0)!;
      final before = fixedContent.substring(0, urlMatch.start).trim();
      final after = fixedContent.substring(urlMatch.end).trim();
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (before.isNotEmpty) Text(before, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : null)),
        Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: (isMe ? Colors.white : C.teal).withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.link, size: 16, color: isMe ? Colors.white70 : C.teal),
            const SizedBox(width: 8),
            Flexible(child: Text(url.length > 40 ? '${url.substring(0, 40)}...' : url,
              style: TextStyle(fontSize: 12, color: isMe ? Colors.white70 : C.teal, decoration: TextDecoration.underline))),
          ])),
        if (after.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
          child: Text(after, style: TextStyle(fontSize: 14, color: isMe ? Colors.white70 : C.text4))),
      ]));
    }

    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(fixedContent, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : null, height: 1.4)));
  }
}

// ── Typing indicator bubble ───────────────────────────────────────────────────

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
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
              color: Colors.black.withOpacity(isDark ? 0.18 : 0.06),
              blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                // Each dot peaks at a different phase (0, 0.33, 0.66 of the cycle).
                final phase = (_ctrl.value - i / 3.0) % 1.0;
                final brightness = (sin(phase * 2 * pi) + 1) / 2; // 0..1
                return Container(
                  width: 7, height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    color: C.teal.withOpacity(0.3 + 0.7 * brightness),
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

// ── Swipeable message wrapper ─────────────────────────────────────────────────

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
    // Spring back
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
        // Reply icon (left side)
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
                    color: C.teal.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.reply_rounded, size: 18, color: C.teal),
                ),
              ),
            ),
          ),
        // Message bubble
        Transform.translate(
          offset: Offset(_dx, 0),
          child: widget.child,
        ),
      ]),
    );
  }
}

// ── Reply preview ─────────────────────────────────────────────────────────────

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
    final text = message['content'] ?? '';
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
              top: BorderSide(color: C.teal.withOpacity(0.2), width: 1),
            ),
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.12 : 0.04),
              blurRadius: 6, offset: const Offset(0, -2),
            )],
          ),
          child: Row(children: [
            Container(width: 3, height: 40, decoration: BoxDecoration(
              color: C.teal, borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(senderName, style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: C.teal,
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
                child: const Icon(Icons.close, size: 14, color: C.text4),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
