import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});
  @override State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _msgs = [];
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _tips(L10n l) {
    final isKZ = l.lang == 'KZ';
    final isEN = l.lang == 'EN';
    return [
      {
        'icon': Icons.menu_book_rounded,
        'title': isKZ ? 'Тақырыпты түсіндір' : isEN ? 'Explain Topic' : 'Объяснить тему',
        'desc':  isKZ ? 'Күрделі тұжырымды қарапайым сөздермен' : isEN ? 'Break down complex concepts in simple words' : 'Разбери сложную концепцию простыми словами',
        'prompt': l.t('tip_explain'),
      },
      {
        'icon': Icons.lightbulb_outline_rounded,
        'title': isKZ ? 'Тұжырымдарды ашу' : isEN ? 'Break Down Concepts' : 'Разобрать концепции',
        'desc':  isKZ ? 'Тәсілдер арасындағы айырмашылықты түсін' : isEN ? 'Understand the difference between approaches' : 'Помоги понять разницу между подходами',
        'prompt': l.t('tip_concepts'),
      },
      {
        'icon': Icons.edit_outlined,
        'title': isKZ ? 'Тапсырмаға көмек' : isEN ? 'Help with Task' : 'Помочь с заданием',
        'desc':  isKZ ? 'Шешімді қайдан бастау керектігін айт' : isEN ? 'Tell me where to start the solution' : 'Подскажи, с чего начать решение',
        'prompt': l.t('tip_help'),
      },
      {
        'icon': Icons.warning_amber_rounded,
        'title': isKZ ? 'Қателерді тап' : isEN ? 'Find Mistakes' : 'Найти ошибки',
        'desc':  isKZ ? 'Кодымды тексеріп, мәселелерді көрсет' : isEN ? 'Review my code and point out issues' : 'Проверь мой код и укажи на проблемы',
        'prompt': l.t('tip_mistakes'),
      },
    ];
  }

  void _send([String? override]) async {
    final text = override ?? _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    HapticFeedback.lightImpact();
    setState(() { _msgs.add({'role': 'user', 'text': text}); _loading = true; });
    _ctrl.clear();
    _scrollDown();
    try {
      final api = context.read<ApiService>();
      final l = context.read<L10n>();
      final sysLang = l.lang == 'KZ' ? 'казахском' : l.lang == 'EN' ? 'английском' : 'русском';
      final apiMsgs = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Ты AI-ассистент образовательной платформы Chatra. Отвечай на $sysLang языке.'},
        ..._msgs.map((m) => {'role': m['role']!, 'content': m['text']!}),
      ];
      final data = await api.aiChat(apiMsgs);
      setState(() => _msgs.add({'role': 'assistant', 'text': data['content'] ?? context.read<L10n>().t('no_answer')}));
    } catch (e) {
      final l = context.read<L10n>();
      setState(() => _msgs.add({'role': 'assistant', 'text': e.toString().contains('503') ? l.t('ai_not_configured') : l.t('connection_error')}));
    }
    setState(() => _loading = false);
    _scrollDown();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final l = context.watch<L10n>();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(children: [
        _buildHeader(isDark, surface, l),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: _msgs.isEmpty
                ? _emptyState(isDark, l)
                : _messageList(isDark),
          ),
        ),
        // Input bar is its own widget — rebuilds independently on keystrokes
        _AiInputBar(ctrl: _ctrl, loading: _loading, onSend: _send),
      ]),
    );
  }

  Widget _buildHeader(bool isDark, Color surface, L10n l) {
    final isKZ = l.lang == 'KZ';
    final isEN = l.lang == 'EN';
    final subtitle = isKZ ? 'Сіздің оқу көмекшіңіз' : isEN ? 'Your learning assistant' : 'Ваш учебный ассистент';

    return SafeArea(bottom: false, child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: surface,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.15)),
          ),
          padding: const EdgeInsets.all(8),
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Chatra AI', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: C.text4, fontWeight: FontWeight.w500)),
        ])),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
          child: _msgs.isNotEmpty
              ? GestureDetector(
                  key: const ValueKey('clear_btn'),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    showDialog(context: context, builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Text('Очистить чат?', style: TextStyle(fontWeight: FontWeight.w800)),
                      content: const Text('История переписки будет удалена', style: TextStyle(color: C.text4)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: C.text4))),
                        TextButton(onPressed: () { Navigator.pop(ctx); setState(() => _msgs.clear()); }, child: const Text('Удалить', style: TextStyle(color: C.red, fontWeight: FontWeight.w700))),
                      ],
                    ));
                  },
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.primary, size: 19),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('empty')),
        ),
      ]),
    ));
  }

  Widget _emptyState(bool isDark, L10n l) {
    final tips = _tips(l);
    final isKZ = l.lang == 'KZ';
    final isEN = l.lang == 'EN';
    final subtitle = isKZ
        ? 'Оқу туралы кез келген нәрсе сұраңыз —\nтүсіндіремін, көмектесемін, тексеремін'
        : isEN
        ? 'Ask anything about your studies —\nI\'ll explain, help, and review'
        : 'Спросите что угодно об учёбе —\nобъясню, помогу, проверю';

    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        key: const ValueKey('empty_state'),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 106, height: 106,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary.withOpacity(0.08)),
              child: Center(
                child: Container(
                  width: 78, height: 78,
                  decoration: BoxDecoration(
                    color: isDark ? C.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.18), blurRadius: 20, offset: const Offset(0, 5)),
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Chatra AI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(fontSize: 13, color: C.text4, height: 1.4), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [
                _tipCard(tips[0], isDark, 0),
                const SizedBox(height: 12),
                _tipCard(tips[2], isDark, 2),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(children: [
                _tipCard(tips[1], isDark, 1),
                const SizedBox(height: 12),
                _tipCard(tips[3], isDark, 3),
              ])),
            ]),
          ]),
        ),
      );
    });
  }

  Widget _tipCard(Map<String, dynamic> tip, bool isDark, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 280 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _send(tip['prompt'] as String);
        },
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
      ),
    );
  }

  Widget _messageList(bool isDark) {
    return ListView.builder(
      key: const ValueKey('msg_list'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      itemCount: _msgs.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _msgs.length) return _typingIndicator();
        final m = _msgs[i];
        final isUser = m['role'] == 'user';
        return TweenAnimationBuilder<double>(
          key: ValueKey('msg_$i'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(isUser ? 18 * (1 - t) : -18 * (1 - t), 8 * (1 - t)), child: child),
          ),
          child: RepaintBoundary(
            child: isUser ? _userMessage(m['text'] ?? '') : _aiMessage(m['text'] ?? '', isDark),
          ),
        );
      },
    );
  }

  Widget _userMessage(String text) {
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

  Widget _aiMessage(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, right: 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44, height: 44,
          margin: const EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2), width: 1.5),
            boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 2))],
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
  }

  Widget _typingIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44, height: 44,
          margin: const EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2), width: 1.5),
            boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), blurRadius: 10)],
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
            child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => _Dot(delay: i * 180))),
          ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input bar — isolated StatefulWidget so keystrokes don't rebuild the whole screen
// ─────────────────────────────────────────────────────────────────────────────
class _AiInputBar extends StatefulWidget {
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onSend;

  const _AiInputBar({required this.ctrl, required this.loading, required this.onSend});

  @override
  State<_AiInputBar> createState() => _AiInputBarState();
}

class _AiInputBarState extends State<_AiInputBar> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_onCtrlChange);
  }

  @override
  void didUpdateWidget(_AiInputBar old) {
    super.didUpdateWidget(old);
    if (old.ctrl != widget.ctrl) {
      old.ctrl.removeListener(_onCtrlChange);
      widget.ctrl.addListener(_onCtrlChange);
    }
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_onCtrlChange);
    super.dispose();
  }

  void _onCtrlChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final l = context.read<L10n>();
    final hasText = widget.ctrl.text.trim().isNotEmpty;
    final isKZ = l.lang == 'KZ';
    final isEN = l.lang == 'EN';
    final hint = isKZ ? 'Chatra AI-дан сұраңыз...' : isEN ? 'Ask Chatra AI...' : 'Спросите Chatra AI...';

    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14,
        (MediaQuery.of(context).viewInsets.bottom + 8).clamp(90.0, double.infinity)),
      decoration: BoxDecoration(
        color: surface,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.06), blurRadius: 14, offset: const Offset(0, -2))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 46),
            decoration: BoxDecoration(
              color: adaptiveSurface2(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hasText ? Theme.of(context).colorScheme.primary.withOpacity(0.35) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: TextField(
              controller: widget.ctrl,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: C.text4, fontSize: 15),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              ),
              onSubmitted: (_) => widget.onSend(),
              maxLines: 4,
              minLines: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: widget.onSend,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: widget.loading
                    ? [surface, surface]
                    : hasText
                        ? [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]
                        : [Theme.of(context).colorScheme.primary.withOpacity(0.55), Theme.of(context).colorScheme.secondary.withOpacity(0.45)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: hasText && !widget.loading
                  ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.38), blurRadius: 14, offset: const Offset(0, 4))]
                  : null,
            ),
            child: widget.loading
                ? Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Theme.of(context).colorScheme.primary)))
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      hasText ? Icons.send_rounded : Icons.send_rounded,
                      key: ValueKey(hasText),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Typing indicator dot
// ─────────────────────────────────────────────────────────────────────────────
class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.repeat(reverse: true);
    });
    _anim = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }

  @override void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: 7, height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.3 + _anim.value * 0.7),
        shape: BoxShape.circle,
      ),
      transform: Matrix4.translationValues(0, -4 * _anim.value, 0),
    ),
  );
}
