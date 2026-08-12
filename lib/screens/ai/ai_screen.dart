import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/ai_thread.dart';
import '../../providers/ai_chats_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tappable.dart';
import 'widgets/ai_conversation_view.dart';
import 'widgets/ai_history_drawer.dart';

/// Главный ИИ-ассистент. Переписка — всегда главный экран вкладки; история
/// чатов не отдельная страница, а drawer, открывающийся поверх неё (свайп
/// с левого края или круглая кнопка сверху).
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});
  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int? _activeThreadId;
  bool _picked = false;

  /// Ключ [AiConversationView] завязан на это, а НЕ на [_activeThreadId]
  /// напрямую. Иначе лениво создающийся тред (null -> id при первой отправке
  /// в новом чате) менял бы ValueKey прямо посреди отправки — Flutter пересоздал
  /// бы виджет и оборвал ещё не сохранённый ответ ИИ (и генерацию названия
  /// вместе с ним). Инкрементируется только при осознанной смене чата.
  int _sessionKey = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<AiChatsProvider>().load();
      _pickInitialThread();
    });
  }

  void _pickInitialThread() {
    if (_picked || !mounted) return;
    final threads = context.read<AiChatsProvider>().threads;
    if (threads.isNotEmpty) {
      setState(() {
        _picked = true;
        _activeThreadId = threads.first.id;
        _sessionKey++;
      });
    } else {
      setState(() => _picked = true);
    }
  }

  /// «Новый чат» просто сбрасывает экран в пустое состояние — тред на бэке
  /// создаётся лениво при первой отправке (см. AiConversationView), иначе
  /// в истории копились бы пустые чаты, если пользователь ничего не написал.
  void _createChat() {
    setState(() {
      _activeThreadId = null;
      _sessionKey++;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _selectThread(AiThread t) {
    setState(() {
      _activeThreadId = t.id;
      _sessionKey++;
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: AiHistoryDrawer(
        activeThreadId: _activeThreadId,
        onSelect: _selectThread,
        onCreate: _createChat,
      ),
      // Кнопка истории — плавающая поверх переписки (как в ChatGPT/Claude),
      // без отдельной полосы-хедера, которая просто отъедала бы экран.
      body: Stack(children: [
        Positioned.fill(
          child: AiConversationView(
            key: ValueKey('conv_$_sessionKey'),
            threadId: _activeThreadId,
            onThreadCreated: (id) => setState(() => _activeThreadId = id),
          ),
        ),
        // Контент едет под статус-бар edge-to-edge — часы/индикаторы теряются
        // на светлом/пёстром фоне сообщений. Лёгкий градиент-подложка (не
        // сплошная плашка) держит их читаемыми, не забирая место у контента.
        const Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: _StatusBarScrim())),
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          child: _HistoryButton(onTap: () => _scaffoldKey.currentState?.openDrawer()),
        ),
      ]),
    );
  }
}

/// Едва заметная подложка под статус-баром для edge-to-edge контента:
/// градиент от фона экрана до прозрачного, а не сплошная плашка — время,
/// Dynamic Island и индикаторы остаются читаемыми поверх любого сообщения,
/// но полезная область экрана не уменьшается (высота — только safe area).
class _StatusBarScrim extends StatelessWidget {
  const _StatusBarScrim();

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final height = MediaQuery.of(context).padding.top + 16;
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg.withValues(alpha: 0.78), bg.withValues(alpha: 0.0)],
        ),
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tappable(
      onTap: onTap,
      label: 'Открыть историю чатов',
      // Кнопка плавает над перепиской, поэтому она из того же материала, что
      // и композер снизу: блюр + полупрозрачная заливка + светлый край,
      // вместо непрозрачного круга с тенью.
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? C.darkSurface2.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.72),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.6),
                width: 0.5,
              ),
              boxShadow: softShadow(isDark),
            ),
            child: Icon(CupertinoIcons.sidebar_left, size: 20, color: adaptiveText1(context)),
          ),
        ),
      ),
    );
  }
}
