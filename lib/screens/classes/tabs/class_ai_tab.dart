import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';

class ClassAiTab extends StatefulWidget {
  final int classId;
  final String className;
  final String lectureContext;
  final List<String> lectureImageUrls;
  const ClassAiTab({
    super.key,
    required this.classId,
    required this.className,
    this.lectureContext = '',
    this.lectureImageUrls = const [],
  });
  @override State<ClassAiTab> createState() => _ClassAiTabState();
}

class _ClassAiTabState extends State<ClassAiTab> with TickerProviderStateMixin {
  final _ctrl   = TextEditingController();
  final List<Map<String, String>> _msgs = [];
  bool _loading = false;
  late final AnimationController _pulseCtrl;
  late final AnimationController _fadeCtrl;

  static const _tips = [
    {'icon': Icons.menu_book_rounded,         'title': 'Объясни материал',  'desc': 'Разбери тему простыми словами'},
    {'icon': Icons.lightbulb_outline_rounded, 'title': 'Ключевые понятия',  'desc': 'Назови главные идеи курса'},
    {'icon': Icons.assignment_outlined,       'title': 'Помощь с заданием', 'desc': 'Подскажи, с чего начать'},
    {'icon': Icons.warning_amber_rounded,     'title': 'Частые ошибки',     'desc': 'Что чаще всего понимают неверно'},
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _fadeCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
  }

  @override
  void dispose() { _pulseCtrl.dispose(); _fadeCtrl.dispose(); _ctrl.dispose(); super.dispose(); }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctrl = PrimaryScrollController.of(context);
      if (ctrl.hasClients) {
        ctrl.animateTo(ctrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _send([String? override]) async {
    final text = override ?? _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() { _msgs.add({'role': 'user', 'text': text}); _loading = true; });
    _ctrl.clear();
    _scrollToBottom();
    try {
      final api = context.read<ApiService>();
      final lectureBlock = widget.lectureContext.isNotEmpty
          ? '\n\nМАТЕРИАЛЫ КУРСА (используй эти знания при ответах):\n${widget.lectureContext}' : '';
      final imgs = widget.lectureImageUrls;
      final List<Map<String, dynamic>> visionPre = imgs.isNotEmpty ? [
        {'role': 'user', 'content': [
          {'type': 'text', 'text': 'Прикреплённые файлы-изображения из материалов курса:'},
          ...imgs.map((url) => {'type': 'image_url', 'image_url': {'url': url, 'detail': 'low'}}),
        ]},
        {'role': 'assistant', 'content': 'Ознакомился с прикреплёнными материалами курса.'},
      ] : [];
      final apiMsgs = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Ты AI-ассистент курса "${widget.className}". Отвечай на русском.$lectureBlock'},
        ...visionPre,
        ..._msgs.map((m) => {'role': m['role']!, 'content': m['text']!}),
      ];
      final data = await api.aiChat(
        apiMsgs,
        classId: widget.classId,
        lectureContext: widget.lectureContext.isNotEmpty ? widget.lectureContext : null,
      );
      if (mounted) { setState(() => _msgs.add({'role': 'assistant', 'text': data['content'] ?? 'Нет ответа'})); _scrollToBottom(); }
    } catch (_) {
      if (mounted) { setState(() => _msgs.add({'role': 'assistant', 'text': 'Ошибка соединения'})); _scrollToBottom(); }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final hasText = _ctrl.text.trim().isNotEmpty;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Column(children: [
      Expanded(child: _msgs.isEmpty ? _emptyState(isDark) : _messageList(isDark)),

      Container(
        padding: EdgeInsets.fromLTRB(12, 9, 12, MediaQuery.of(context).padding.bottom + 9),
        decoration: BoxDecoration(
          color: surface,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.18 : 0.05), blurRadius: 12, offset: const Offset(0, -2))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Container(
            decoration: BoxDecoration(
              color: adaptiveSurface2(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: hasText ? Theme.of(context).colorScheme.primary.withOpacity(0.28) : Colors.transparent, width: 1.5),
            ),
            child: TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                hintText: 'Спросите об этом курсе...',
                hintStyle: const TextStyle(fontSize: 15, color: C.text4),
                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                filled: false, contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              ),
              onSubmitted: (_) => _send(),
              maxLines: 4, minLines: 1,
              onChanged: (_) => setState(() {}),
            ),
          )),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _send,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _loading
                      ? [surface, surface]
                      : hasText
                          ? [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]
                          : [Theme.of(context).colorScheme.primary.withOpacity(0.55), Theme.of(context).colorScheme.secondary.withOpacity(0.45)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                boxShadow: hasText && !_loading ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.38), blurRadius: 14, offset: const Offset(0, 4))] : null,
              ),
              child: _loading
                  ? Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Theme.of(context).colorScheme.primary)))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ),
    ]));
  }

  Widget _emptyState(bool isDark) {
    final shortName = widget.className.length > 22 ? '${widget.className.substring(0, 22)}…' : widget.className;
    return FadeTransition(
      opacity: _fadeCtrl,
      child: LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) {
                final v = _pulseCtrl.value;
                return Stack(alignment: Alignment.center, children: [
                  Container(width: 106, height: 106, decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary.withOpacity(0.04 + v * 0.04))),
                  Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary.withOpacity(0.07 + v * 0.04),
                    boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.10 + v * 0.06), blurRadius: 20)])),
                  Container(width: 60, height: 60,
                    decoration: BoxDecoration(color: isDark ? C.darkSurface : Colors.white, borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.18), blurRadius: 20, offset: const Offset(0, 5))]),
                    padding: const EdgeInsets.all(12),
                    child: Image.asset('assets/logo.png', fit: BoxFit.contain)),
                ]);
              }),
              const SizedBox(height: 14),
              Text('Чат по курсу', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: adaptiveText1(context))),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(16)),
                child: Text(shortName, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 20),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: [
                  _tipCard(_tips[0], isDark),
                  const SizedBox(height: 12),
                  _tipCard(_tips[2], isDark),
                ])),
                const SizedBox(width: 12),
                Expanded(child: Column(children: [
                  _tipCard(_tips[1], isDark),
                  const SizedBox(height: 12),
                  _tipCard(_tips[3], isDark),
                ])),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  Widget _tipCard(Map<String, dynamic> tip, bool isDark) {
    return GestureDetector(
      onTap: () => _send(tip['title'] as String),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? C.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: cardShadow(isDark),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
            child: Icon(tip['icon'] as IconData, size: 20, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 14),
          Text(tip['title'] as String, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: adaptiveText1(context), height: 1.2)),
          const SizedBox(height: 6),
          Text(tip['desc'] as String, style: const TextStyle(fontSize: 12, color: C.text4, height: 1.4)),
        ]),
      ),
    );
  }

  Widget _messageList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      itemCount: _msgs.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _msgs.length) return _typingIndicator(isDark);
        final m   = _msgs[i];
        final isU = m['role'] == 'user';
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(
            offset: Offset(isU ? 16*(1-t) : -16*(1-t), 6*(1-t)), child: child)),
          child: isU ? _userBubble(m['text'] ?? '') : _aiBubble(m['text'] ?? '', isDark),
        );
      },
    );
  }

  Widget _userBubble(String text) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22), topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22), bottomRight: Radius.circular(6),
            ),
            boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.28), blurRadius: 16, offset: const Offset(0, 5))],
          ),
          child: Text(text, style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.5)),
        ),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(timeStr, style: const TextStyle(fontSize: 10, color: C.text4)),
          const SizedBox(width: 4),
          Icon(Icons.done_all_rounded, size: 13, color: Theme.of(context).colorScheme.primary),
        ]),
      ]),
    );
  }

  Widget _aiBubble(String text, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 20, right: 24),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 44, height: 44,
        margin: const EdgeInsets.only(top: 2, right: 10),
        decoration: BoxDecoration(
          color: isDark ? C.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2), width: 1.5),
          boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.10), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(8),
        child: Image.asset('assets/logo.png', fit: BoxFit.contain),
      ),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.only(left: 2, bottom: 5),
          child: Text('Chatra AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 0.2))),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6), topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20),
            ),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(isDark ? 0.12 : 0.08)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.05), blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: SelectableText(text, style: const TextStyle(fontSize: 15, height: 1.7, letterSpacing: 0.1)),
        ),
      ])),
    ]),
  );

  Widget _typingIndicator(bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 16, right: 24),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 44, height: 44,
        margin: const EdgeInsets.only(top: 2, right: 10),
        decoration: BoxDecoration(
          color: isDark ? C.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2), width: 1.5),
          boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.10), blurRadius: 10)],
        ),
        padding: const EdgeInsets.all(8),
        child: Image.asset('assets/logo.png', fit: BoxFit.contain),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.only(left: 2, bottom: 5),
          child: Text('Chatra AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6), topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20),
            ),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(isDark ? 0.12 : 0.08)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 10)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => _ClassAiDot(delay: i * 180))),
        ),
      ]),
    ]),
  );
}

class _ClassAiDot extends StatefulWidget {
  final int delay;
  const _ClassAiDot({required this.delay});
  @override State<_ClassAiDot> createState() => _ClassAiDotState();
}
class _ClassAiDotState extends State<_ClassAiDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: 500));
    Future.delayed(Duration(milliseconds: widget.delay), () { if (mounted) _c.repeat(reverse: true); });
    _a = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _a, builder: (_, __) => Container(
    width: 7, height: 7, margin: EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.3 + _a.value * 0.7), shape: BoxShape.circle),
    transform: Matrix4.translationValues(0, -4 * _a.value, 0),
  ));
}
