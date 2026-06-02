import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with SingleTickerProviderStateMixin {
  List<dynamic> _chats = [];
  Map<int, List<dynamic>> _messages = {};
  Map<int, List<dynamic>> _chatUsers = {};
  int? _activeChatId;
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  List<dynamic> _searchResults = [];
  Timer? _poller;
  late AnimationController _listAnim;
  // Tracks the created_at of the last message seen per chat
  final Map<int, String> _lastReadAt = {};

  static const _avatarColors = [C.teal, Color(0xFF6366F1), Color(0xFFF59E0B), Color(0xFF0891B2), Color(0xFFEC4899), Color(0xFF059669), Color(0xFFD97706), Color(0xFF64748B)];

  @override void initState() {
    super.initState();
    _listAnim = AnimationController(vsync: this, duration: Duration(milliseconds: 600));
    _loadChats();
    _poller = Timer.periodic(Duration(seconds: 5), (_) => _pollMessages());
  }
  @override void dispose() { _poller?.cancel(); _listAnim.dispose(); super.dispose(); }

  Future<void> _loadChats() async {
    if (!mounted) return; setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      _chats = await api.getChats();
      for (final c in _chats) {
        final id = c['id'] as int;
        try { _chatUsers[id] = await api.getChatUsers(id); } catch (_) {}
        try { _messages[id] = await api.getMessages(id); } catch (_) {}
      }
    } catch (_) {}
    if (mounted) { setState(() => _loading = false); _listAnim.forward(from: 0); }
  }

  Future<void> _pollMessages() async {
    if (_activeChatId == null) return;
    try {
      final msgs = await context.read<ApiService>().getMessages(_activeChatId!);
      if (mounted) setState(() {
        _messages[_activeChatId!] = msgs;
        if (msgs.isNotEmpty) _lastReadAt[_activeChatId!] = msgs.last['created_at'] ?? '';
      });
    } catch (_) {}
  }

  String _chatTitle(dynamic chat) {
    final auth = context.read<AuthProvider>();
    final users = _chatUsers[chat['id']] ?? [];
    final other = users.where((u) => u['id'] != auth.userId).toList();
    if (other.isNotEmpty) return other.first['full_name'] ?? other.first['email']?.split('@').first ?? 'Chat';
    final name = chat['name'] ?? '';
    return name.startsWith('Чат с ') ? name.substring(6) : name;
  }

  String _lastPreview(int id) { final msgs = _messages[id] ?? []; if (msgs.isEmpty) return 'Нет сообщений'; final content = msgs.last['content'] ?? ''; return content.length > 45 ? '${content.substring(0, 45)}...' : content; }

  String _chatTime(int id) {
    final msgs = _messages[id] ?? []; if (msgs.isEmpty) return '';
    try {
      final d = DateTime.parse(msgs.last['created_at']); final now = DateTime.now();
      if (now.difference(d).inMinutes < 1) return 'сейчас';
      if (now.difference(d).inHours < 24) return '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
      if (now.difference(d).inDays == 1) return 'вчера';
      return '${d.day}.${d.month.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  bool _hasUnread(int id) {
    final msgs = _messages[id] ?? [];
    if (msgs.isEmpty) return false;
    final auth = context.read<AuthProvider>();
    final last = msgs.last;
    if (last['user_id'] == auth.userId) return false;
    final lastReadAt = _lastReadAt[id];
    if (lastReadAt == null || lastReadAt.isEmpty) return true;
    try {
      return DateTime.parse(last['created_at']).isAfter(DateTime.parse(lastReadAt));
    } catch (_) {
      return false;
    }
  }

  void _searchUsers(String q) async {
    if (q.trim().isEmpty) { setState(() => _searchResults = []); return; }
    try {
      final all = await context.read<ApiService>().getUsers();
      final auth = context.read<AuthProvider>();
      if (mounted) setState(() { _searchResults = all.where((u) => u['id'] != auth.userId && ((u['email'] ?? '').toLowerCase().contains(q.toLowerCase()) || (u['full_name'] ?? '').toLowerCase().contains(q.toLowerCase()))).toList(); });
    } catch (_) {}
  }

  Future<void> _openDM(dynamic user) async {
    final auth = context.read<AuthProvider>();
    for (final c in _chats) { final users = _chatUsers[c['id']] ?? []; if (users.length == 2 && users.any((u) => u['id'] == user['id']) && users.any((u) => u['id'] == auth.userId)) { setState(() { _activeChatId = c['id']; _searchCtrl.clear(); _searchResults = []; }); return; } }
    try { final api = context.read<ApiService>(); final chat = await api.createChat('Чат с ${user['email']}'); await api.addChatUser(chat['id'], user['id']); _searchCtrl.clear(); _searchResults = []; await _loadChats(); setState(() => _activeChatId = chat['id']); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_activeChatId != null) return _buildChatView();
    return _buildChatList();
  }

  Widget _buildChatList() {
    final l = context.watch<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 0), child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('messages_title'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: C.teal)),
            Text(l.t('your_conversations'), style: TextStyle(fontSize: 13, color: C.text4)),
          ]),
          Spacer(),
          // New chat button
          GestureDetector(
            onTap: () { FocusScope.of(context).requestFocus(FocusNode()); showToast(context, l.t('find_user_hint')); },
            child: Container(width: 44, height: 44, decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.edit_outlined, color: Colors.white, size: 20))),
        ])),
        SizedBox(height: 16),
        // Search bar
        Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Container(
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.04), blurRadius: 8, offset: Offset(0, 2))]),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Найти или начать диалог...',
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: C.text4),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.symmetric(vertical: 14)),
            onChanged: _searchUsers,
          ))),
        // Search results
        if (_searchResults.isNotEmpty) Container(
          constraints: BoxConstraints(maxHeight: 220), margin: EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12)]),
          child: ClipRRect(borderRadius: BorderRadius.circular(16), child: ListView(shrinkWrap: true,
            children: _searchResults.map((u) {
              final color = _avatarColors[(u['id'] ?? 0) % _avatarColors.length];
              final initials = (u['full_name'] ?? u['email'] ?? '?')[0].toUpperCase();
              return ListTile(
                leading: CircleAvatar(radius: 22, backgroundColor: color.withOpacity(0.15),
                  child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16))),
                title: Text(u['full_name'] ?? u['email']?.split('@').first ?? '', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: Text(u['email'] ?? '', style: TextStyle(fontSize: 12, color: C.text4)),
                onTap: () => _openDM(u),
              );
            }).toList()))),
        SizedBox(height: 8),
        // Chat list
        Expanded(child: _loading
          ? Center(child: CircularProgressIndicator(color: C.teal, strokeWidth: 2.5))
          : _chats.isEmpty
            ? _emptyState()
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: _chats.length,
                itemBuilder: (ctx, i) {
                  final c = _chats[i]; final id = c['id'] as int;
                  final color = _avatarColors[id % _avatarColors.length];
                  final title = _chatTitle(c);
                  final unread = _hasUnread(id);
                  final time = _chatTime(id);
                  final preview = _lastPreview(id);
                  final initials = title.isNotEmpty ? title[0].toUpperCase() : '?';

                  return TweenAnimationBuilder<double>(
                    key: ValueKey(id),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 300 + i * 60),
                    curve: Curves.easeOutCubic,
                    builder: (_, t, child) => Transform.translate(offset: Offset(0, 20 * (1 - t)), child: Opacity(opacity: t, child: child)),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _activeChatId = id;
                          final msgs = _messages[id] ?? [];
                          if (msgs.isNotEmpty) _lastReadAt[id] = msgs.last['created_at'] ?? '';
                        });
                      },
                      child: Container(
                        margin: EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 10, offset: Offset(0, 2))],
                        ),
                        child: Padding(padding: EdgeInsets.all(14), child: Row(children: [
                          // Avatar with online dot
                          Stack(children: [
                            Container(width: 52, height: 52, decoration: BoxDecoration(gradient: RadialGradient(colors: [color.withOpacity(0.3), color.withOpacity(0.12)]), shape: BoxShape.circle),
                              child: Center(child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20)))),
                            if (unread) Positioned(right: 0, bottom: 0,
                              child: Container(width: 14, height: 14, decoration: BoxDecoration(color: C.teal, shape: BoxShape.circle, border: Border.all(color: surface, width: 2)))),
                          ]),
                          SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: unread ? FontWeight.w800 : FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              if (time.isNotEmpty) Text(time, style: TextStyle(fontSize: 11, color: unread ? C.teal : C.text4, fontWeight: unread ? FontWeight.w700 : FontWeight.w400)),
                            ]),
                            SizedBox(height: 4),
                            Row(children: [
                              Expanded(child: Text(preview, style: TextStyle(fontSize: 13, color: unread ? adaptiveText1(context) : C.text4, fontWeight: unread ? FontWeight.w500 : FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              if (unread) Container(width: 8, height: 8, margin: EdgeInsets.only(left: 8), decoration: BoxDecoration(color: C.teal, shape: BoxShape.circle)),
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
        child: Icon(Icons.chat_bubble_outline_rounded, size: 36, color: C.teal)),
      SizedBox(height: 16),
      Text(l.t('no_chats'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
      SizedBox(height: 6),
      Text(l.t('search_above'), style: TextStyle(fontSize: 14, color: C.text4)),
    ]));
  }

  Widget _buildChatView() {
    final l = context.watch<L10n>();
    final msgs = _messages[_activeChatId] ?? [];
    final chat = _chats.firstWhere((c) => c['id'] == _activeChatId, orElse: () => {'name': 'Chat'});
    final msgCtrl = TextEditingController();
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _chatTitle(chat);
    final color = _avatarColors[(_activeChatId ?? 0) % _avatarColors.length];
    final scrollCtrl = ScrollController();

    void send() async {
      if (msgCtrl.text.trim().isEmpty) return;
      HapticFeedback.lightImpact();
      try {
        await context.read<ApiService>().sendMessage(_activeChatId!, msgCtrl.text.trim());
        msgCtrl.clear();
        _pollMessages();
        Future.delayed(Duration(milliseconds: 100), () { if (scrollCtrl.hasClients) scrollCtrl.animateTo(scrollCtrl.position.maxScrollExtent, duration: Duration(milliseconds: 300), curve: Curves.easeOut); });
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(preferredSize: Size.fromHeight(64), child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 8)],
        ),
        child: SafeArea(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Row(children: [
          IconButton(icon: Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () {
            HapticFeedback.lightImpact();
            setState(() {
              if (_activeChatId != null) {
                final msgs = _messages[_activeChatId!] ?? [];
                if (msgs.isNotEmpty) _lastReadAt[_activeChatId!] = msgs.last['created_at'] ?? '';
              }
              _activeChatId = null;
            });
          }),
          Container(width: 38, height: 38, decoration: BoxDecoration(gradient: RadialGradient(colors: [color.withOpacity(0.3), color.withOpacity(0.12)]), shape: BoxShape.circle),
            child: Center(child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)))),
          SizedBox(width: 10),
          Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
        ]))))),
      body: Column(children: [
        Expanded(child: msgs.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.waving_hand_outlined, size: 48, color: C.teal.withOpacity(0.4)),
              SizedBox(height: 12),
              Text(l.t('start_dialog'), style: TextStyle(fontSize: 16, color: C.text4, fontWeight: FontWeight.w500)),
            ]))
          : ListView.builder(
              controller: scrollCtrl,
              padding: EdgeInsets.fromLTRB(12, 16, 12, 8),
              itemCount: msgs.length,
              itemBuilder: (ctx, i) {
                final m = msgs[i]; final isMe = m['user_id'] == auth.userId;
                final showTime = i == msgs.length - 1 || (msgs[i + 1]['user_id'] != m['user_id']);
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 200),
                  builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(isMe ? 20 * (1 - t) : -20 * (1 - t), 0), child: child)),
                  child: Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: EdgeInsets.only(bottom: showTime ? 12 : 3),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                      decoration: BoxDecoration(
                        gradient: isMe ? LinearGradient(colors: [C.teal, C.tealDk], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                        color: isMe ? null : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20), topRight: Radius.circular(20),
                          bottomLeft: Radius.circular(isMe ? 20 : 6),
                          bottomRight: Radius.circular(isMe ? 6 : 20)),
                        boxShadow: [BoxShadow(color: isMe ? C.teal.withOpacity(0.25) : Colors.black.withOpacity(isDark ? 0.2 : 0.08), blurRadius: 12, offset: Offset(0, 3))],
                      ),
                      child: _buildMessageContent(m['content'] ?? '', isMe),
                    ),
                  ),
                );
              })),
        // Input bar
        Container(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 90),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.06), blurRadius: 12, offset: Offset(0, -2))],
          ),
          child: Row(children: [
            // Photo attachment: gallery + camera
            GestureDetector(onTap: () => _showPhotoMenu(context, _activeChatId!, () => _pollMessages()),
              child: Container(width: 40, height: 40, margin: EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.add_rounded, size: 22, color: C.teal))),
            Expanded(child: Container(
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(24)),
              child: TextField(
                controller: msgCtrl,
                decoration: InputDecoration(hintText: l.t('message'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                onSubmitted: (_) => send(),
                maxLines: 4, minLines: 1,
              ))),
            SizedBox(width: 8),
            GestureDetector(
              onTap: send,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.9, end: 1.0),
                duration: Duration(milliseconds: 150),
                builder: (_, t, child) => Transform.scale(scale: t, child: child),
                child: Container(width: 48, height: 48,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [C.teal, C.tealDk], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: C.teal.withOpacity(0.4), blurRadius: 12, offset: Offset(0, 4))]),
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 20)),
              )),
          ]),
        ),
      ]),
    );
  }

  void _showPhotoMenu(BuildContext context, int chatId, VoidCallback onDone) {
    showModalBottomSheet(context: context, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: C.text4.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          SizedBox(height: 20),
          _photoOption(ctx, Icons.photo_library_rounded, 'Галерея', () async {
            Navigator.pop(ctx);
            final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
            if (img != null) await _uploadAndSend(chatId, img, onDone);
          }),
          SizedBox(height: 8),
          _photoOption(ctx, Icons.camera_alt_rounded, 'Камера', () async {
            Navigator.pop(ctx);
            final img = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1200, imageQuality: 85);
            if (img != null) await _uploadAndSend(chatId, img, onDone);
          }),
        ]),
      )),
    );
  }

  Widget _photoOption(BuildContext ctx, IconData icon, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: adaptiveSurface2(ctx), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: C.teal)),
        SizedBox(width: 14),
        Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        Spacer(),
        Icon(Icons.chevron_right, size: 20, color: C.text4),
      ]),
    ),
  );

  Future<void> _uploadAndSend(int chatId, XFile img, VoidCallback onDone) async {
    try {
      final api = context.read<ApiService>();
      final result = await api.uploadFile(img.path, img.name);
      var url = result['url'] ?? result['file_url'] ?? result['path'] ?? '';
      // Make sure URL is absolute
      if (url.isNotEmpty && !url.startsWith('http')) {
        url = '${api.baseUrl}${url.startsWith('/') ? '' : '/'}$url';
      }
      if (url.isNotEmpty) { await api.sendMessage(chatId, url); onDone(); }
    } catch (e) { if (mounted) showToast(context, 'Ошибка загрузки: $e', error: true); }
  }

  Widget _buildMessageContent(String content, bool isMe) {
    // Fix localhost URLs to use the actual server
    String fixedContent = content;
    try {
      final api = context.read<ApiService>();
      fixedContent = content
          .replaceAll(RegExp(r'https?://localhost:\d+'), api.baseUrl)
          .replaceAll(RegExp(r'https?://127\.0\.0\.1:\d+'), api.baseUrl);
    } catch (_) {}

    // Check for image URL in content
    final imgRegex = RegExp(r'https?://\S+\.(jpg|jpeg|png|gif|webp)', caseSensitive: false);
    final imgMatch = imgRegex.firstMatch(fixedContent);
    if (imgMatch != null) {
      final url = imgMatch.group(0)!;
      final textPart = fixedContent.replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '').replaceAll(url, '').trim();
      return ClipRRect(borderRadius: BorderRadius.circular(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Image.network(url, fit: BoxFit.cover, width: double.infinity, height: 200,
          loadingBuilder: (_, child, progress) => progress == null ? child : Container(height: 200, color: adaptiveSurface2(context), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.teal))),
          errorBuilder: (_, __, ___) => Container(height: 80, padding: EdgeInsets.all(16), child: Row(children: [Icon(Icons.broken_image, color: C.text4), SizedBox(width: 8), Flexible(child: Text(url.split('/').last, style: TextStyle(color: isMe ? Colors.white70 : C.text4, fontSize: 12)))]))),
        if (textPart.isNotEmpty) Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 10), child: Text(textPart, style: TextStyle(fontSize: 14, color: isMe ? Colors.white : null))),
      ]));
    }

    // Check for any URL
    final urlRegex = RegExp(r'https?://\S+');
    final urlMatch = urlRegex.firstMatch(fixedContent);
    if (urlMatch != null) {
      final url = urlMatch.group(0)!;
      final before = fixedContent.substring(0, urlMatch.start).trim();
      final after = fixedContent.substring(urlMatch.end).trim();
      return Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (before.isNotEmpty) Text(before, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : null)),
        Container(margin: EdgeInsets.only(top: 6), padding: EdgeInsets.all(10),
          decoration: BoxDecoration(color: (isMe ? Colors.white : C.teal).withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [Icon(Icons.link, size: 16, color: isMe ? Colors.white70 : C.teal), SizedBox(width: 8),
            Flexible(child: Text(url.length > 40 ? '${url.substring(0, 40)}...' : url, style: TextStyle(fontSize: 12, color: isMe ? Colors.white70 : C.teal, decoration: TextDecoration.underline)))])),
        if (after.isNotEmpty) Padding(padding: EdgeInsets.only(top: 4), child: Text(after, style: TextStyle(fontSize: 14, color: isMe ? Colors.white70 : C.text4))),
      ]));
    }

    return Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(fixedContent, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : null, height: 1.4)));
  }
}
