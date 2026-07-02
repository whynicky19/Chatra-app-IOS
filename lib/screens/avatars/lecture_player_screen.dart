import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../models/avatar_models.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

class LecturePlayerScreen extends StatefulWidget {
  final int lectureId;
  const LecturePlayerScreen({super.key, required this.lectureId});
  @override
  State<LecturePlayerScreen> createState() => _LecturePlayerScreenState();
}

class _LecturePlayerScreenState extends State<LecturePlayerScreen> {
  bool _loading = true;
  String? _loadError;
  AvatarLectureFull? _full;

  int _slideIndex = 0;
  bool _showingSummary = false;

  final AudioPlayer _audio = AudioPlayer();
  VideoPlayerController? _introVideo;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  bool _isPlaying = false;
  bool _isSpeaking = false;
  Duration _duration = Duration.zero;
  final Map<int, double> _slideProgress = {}; // 0..1 per slide index, 1 = fully watched

  @override
  void initState() {
    super.initState();
    _load();
    _playerStateSub = _audio.playerStateStream.listen(_onPlayerState);
    _positionSub = _audio.positionStream.listen((p) {
      if (!mounted || _duration.inMilliseconds <= 0) return;
      setState(() {
        _slideProgress[_slideIndex] = (p.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
      });
    });
    _durationSub = _audio.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    });
  }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    try {
      final json = await api.getAvatarLectureFull(widget.lectureId);
      final full = AvatarLectureFull.fromJson(json, api);
      if (!mounted) return;
      setState(() { _full = full; _loading = false; });
      await _setupIntroVideoIfNeeded();
      await _playCurrentSlide(autoplay: true);
    } catch (_) {
      if (!mounted) return;
      setState(() { _loadError = 'error'; _loading = false; });
    }
  }

  Future<void> _setupIntroVideoIfNeeded() async {
    final url = _full?.lecture.introVideoUrl;
    if (url == null || url.isEmpty) return;
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted) { controller.dispose(); return; }
      await controller.setLooping(true);
      await controller.setVolume(0);
      setState(() => _introVideo = controller);
      if (_slideIndex == 0) controller.play();
    } catch (_) {
      // Fall back silently to photo/placeholder.
    }
  }

  void _onPlayerState(PlayerState state) {
    if (!mounted) return;
    setState(() {
      _isPlaying = state.playing;
      _isSpeaking = state.playing && state.processingState == ProcessingState.ready;
    });
    if (state.processingState == ProcessingState.completed) {
      _onSlideAudioComplete();
    }
  }

  Future<void> _onSlideAudioComplete() async {
    if (!mounted) return;
    setState(() => _slideProgress[_slideIndex] = 1.0);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final slides = _full?.slides ?? [];
    if (_slideIndex < slides.length - 1) {
      await _goToSlide(_slideIndex + 1, autoplay: true);
    }
  }

  Future<void> _playCurrentSlide({bool autoplay = false}) async {
    final slides = _full?.slides ?? [];
    if (_slideIndex >= slides.length) return;
    final slide = slides[_slideIndex];
    if (slide.audioUrl == null || slide.audioUrl!.isEmpty) return;
    try {
      await _audio.setUrl(slide.audioUrl!);
      if (!mounted) return;
      if (autoplay) await _audio.play();
    } catch (_) {
      if (mounted) showToast(context, context.read<L10n>().t('error'), error: true);
    }
  }

  Future<void> _goToSlide(int index, {bool autoplay = false}) async {
    final slides = _full?.slides ?? [];
    if (index < 0 || index >= slides.length) return;
    await _audio.stop();
    if (!mounted) return;
    setState(() {
      _slideIndex = index;
      _duration = Duration.zero;
      _slideProgress[index] = 0.0;
    });
    _introVideo?.pause();
    if (index == 0) _introVideo?.play();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _playCurrentSlide(autoplay: autoplay);
  }

  Future<void> _togglePlayPause() async {
    if (_audio.playing) {
      await _audio.pause();
    } else {
      if (_audio.processingState == ProcessingState.idle) {
        await _playCurrentSlide(autoplay: true);
      } else {
        await _audio.play();
      }
    }
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _audio.dispose();
    _introVideo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    if (_loading) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    if (_loadError != null || _full == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.white54, size: 40),
          const SizedBox(height: 12),
          Text(l.t('error'), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l.t('cancel'), style: const TextStyle(color: Colors.white))),
        ])),
      );
    }

    if (_showingSummary) return _buildSummaryView(l);

    final slides = _full!.slides;
    final slide = slides.isNotEmpty ? slides[_slideIndex] : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(l, slides.length),
          _buildProgressBar(slides.length),
          Expanded(child: Stack(children: [
            Center(child: slide?.slideImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: slide!.slideImageUrl!,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const CircularProgressIndicator(color: Colors.white38),
                    errorWidget: (_, __, ___) => Text(l.t('slide_preparing'), style: const TextStyle(color: Colors.white38)),
                  )
                : Text(l.t('slide_preparing'), style: const TextStyle(color: Colors.white38))),
            Positioned(bottom: 12, right: 12, child: _buildAvatarCircle()),
          ])),
          if (slide?.narrationText != null && slide!.narrationText!.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
              child: SingleChildScrollView(child: Text(slide.narrationText!, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5))),
            ),
          _buildControls(l, slides.length),
        ]),
      ),
    );
  }

  Widget _buildHeader(L10n l, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_full!.lecture.title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (total > 0) Text('${l.t('slide_label')} ${_slideIndex + 1} ${l.t('of_label')} $total', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
        if (_full!.lecture.summaryText != null && _full!.lecture.summaryText!.isNotEmpty)
          GestureDetector(
            onTap: () => setState(() => _showingSummary = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(CupertinoIcons.doc_text, size: 14, color: Colors.white),
                const SizedBox(width: 5),
                Text(l.t('summary'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 16)),
        ),
      ]),
    );
  }

  Widget _buildProgressBar(int total) {
    if (total == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: List.generate(total, (i) {
        final progress = i < _slideIndex ? 1.0 : (i == _slideIndex ? (_slideProgress[i] ?? 0.0) : 0.0);
        return Expanded(child: Container(
          height: 3,
          margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
          ),
        ));
      })),
    );
  }

  Widget _buildAvatarCircle() {
    final showVideo = _slideIndex == 0 && _introVideo != null && _introVideo!.value.isInitialized;
    final photo = _full!.avatarPhotoUrl;
    return Container(
      width: 72, height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _isSpeaking ? Theme.of(context).colorScheme.primary : Colors.white24, width: _isSpeaking ? 3 : 1.5),
        boxShadow: _isSpeaking ? primaryGlow(Theme.of(context).colorScheme.primary, opacity: 0.5) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        if (showVideo)
          FittedBox(fit: BoxFit.cover, child: SizedBox(
            width: _introVideo!.value.size.width, height: _introVideo!.value.size.height,
            child: VideoPlayer(_introVideo!)))
        else if (photo != null)
          CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(color: C.darkSurface2, child: const Icon(CupertinoIcons.person_fill, color: Colors.white38)))
        else
          Container(color: C.darkSurface2, child: const Icon(CupertinoIcons.person_fill, color: Colors.white38)),
        if (_isSpeaking) Positioned(bottom: 4, left: 0, right: 0, child: _SpeakingDots()),
      ]),
    );
  }

  Widget _buildControls(L10n l, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _controlBtn(CupertinoIcons.backward_fill, _slideIndex > 0 ? () => _goToSlide(_slideIndex - 1, autoplay: true) : null),
        const SizedBox(width: 28),
        GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            width: 62, height: 62,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary,
              boxShadow: primaryGlow(Theme.of(context).colorScheme.primary, opacity: 0.4)),
            child: Icon(_isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(width: 28),
        _controlBtn(CupertinoIcons.forward_fill, _slideIndex < total - 1 ? () => _goToSlide(_slideIndex + 1, autoplay: true) : null),
      ]),
    );
  }

  Widget _controlBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46, height: 46,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: enabled ? 0.12 : 0.04)),
        child: Icon(icon, color: Colors.white.withValues(alpha: enabled ? 1 : 0.3), size: 20),
      ),
    );
  }

  Widget _buildSummaryView(L10n l) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(l.t('summary')),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => setState(() => _showingSummary = false),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: renderSimpleMarkdown(_full!.lecture.summaryText ?? '', context)),
      ),
    );
  }
}

class _SpeakingDots extends StatefulWidget {
  @override
  State<_SpeakingDots> createState() => _SpeakingDotsState();
}

class _SpeakingDotsState extends State<_SpeakingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_ctrl.value + i * 0.2) % 1.0;
            final scale = 0.5 + 0.5 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Transform.scale(scale: scale, child: Container(
                width: 5, height: 5,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              )),
            );
          }));
      },
    );
  }
}

/// Minimal, self-contained markdown renderer for AI-generated summaries.
/// Supports #/##/### headers, **bold** spans and "- " list items. No HTML,
/// no external markdown package — avoids pulling in a dependency for a
/// narrow use case and any injection surface that comes with v-html-style
/// rendering.
List<Widget> renderSimpleMarkdown(String text, BuildContext context) {
  final widgets = <Widget>[];
  final lines = text.split('\n');
  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) { widgets.add(const SizedBox(height: 8)); continue; }
    if (line.startsWith('### ')) {
      widgets.add(Padding(padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(line.substring(4), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))));
    } else if (line.startsWith('## ')) {
      widgets.add(Padding(padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(line.substring(3), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))));
    } else if (line.startsWith('# ')) {
      widgets.add(Padding(padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(line.substring(2), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))));
    } else if (line.trimLeft().startsWith('- ')) {
      final content = line.trimLeft().substring(2);
      widgets.add(Padding(padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  ', style: TextStyle(fontSize: 14, height: 1.5)),
          Expanded(child: _boldRichText(content, const TextStyle(fontSize: 14, height: 1.5))),
        ])));
    } else {
      widgets.add(Padding(padding: const EdgeInsets.only(bottom: 4),
        child: _boldRichText(line, const TextStyle(fontSize: 14, height: 1.6))));
    }
  }
  return widgets;
}

/// Renders a line with **bold** spans as RichText; plain text otherwise.
Widget _boldRichText(String line, TextStyle base) {
  final parts = line.split('**');
  if (parts.length == 1) return Text(line, style: base);
  final spans = <TextSpan>[];
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    spans.add(TextSpan(text: parts[i], style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w800) : base));
  }
  return RichText(text: TextSpan(style: base, children: spans));
}
