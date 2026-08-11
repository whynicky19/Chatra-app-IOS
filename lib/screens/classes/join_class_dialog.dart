import 'dart:async';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/classes_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_cache.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/network_cover_image.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';

/// Диалог ввода кода приглашения — оформлен в стиле остального приложения
/// (нейтральные поверхности, акцентный цвет только у кнопки и активной
/// рамки поля), но без синего фона/иконки, как было раньше.
///
/// Presentation — через `showAppDialog`/`AppDialogCard` (тот же spring-bounce
/// вход, тот же `AppRadii.card`, тот же фон), что и у всех остальных диалогов
/// приложения (`showConfirmDialog`, `showInputDialog`). Раньше это был голый
/// Material `Dialog` с дефолтным плоским fade — единственный диалог в
/// приложении с другим "мотором" появления.
Future<void> showJoinClassDialog(BuildContext context) {
  return showAppDialog(context,
    builder: (_) => const AppDialogCard(child: _JoinClassDialogContent()),
  );
}

class _JoinClassDialogContent extends StatefulWidget {
  const _JoinClassDialogContent();
  @override
  State<_JoinClassDialogContent> createState() => _JoinClassDialogContentState();
}

class _JoinClassDialogContentState extends State<_JoinClassDialogContent> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  bool _busy = false;
  bool _lookingUp = false;
  bool _notFound = false;
  Map<String, dynamic>? _foundClass;
  Timer? _lookupDebounce;

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    // Диалог завершает Future ещё до начала анимации закрытия — если во
    // время закрытия клавиатура тоже уходит, ещё видимые TextField
    // перестраиваются с уже задиспоженным контроллером. Даём закрывающей
    // анимации время закончиться перед dispose().
    Future.delayed(const Duration(milliseconds: 400), () {
      for (final c in _controllers) { c.dispose(); }
      for (final f in _focusNodes) { f.dispose(); }
    });
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text.toUpperCase()).join();

  void _scheduleLookup(String code) {
    _lookupDebounce?.cancel();
    if (code.length < 6) {
      setState(() { _foundClass = null; _notFound = false; _lookingUp = false; });
      return;
    }
    setState(() { _lookingUp = true; _foundClass = null; _notFound = false; });
    _lookupDebounce = Timer(const Duration(milliseconds: 400), () async {
      final api = context.read<ApiService>();
      try {
        final cls = await api.lookupClassByCode(code);
        if (!mounted || _code != code) return;
        setState(() {
          _lookingUp = false;
          _foundClass = {...cls, 'title': cls['name'], 'teacher_name': cls['teacher']};
        });
      } catch (_) {
        if (!mounted || _code != code) return;
        setState(() { _lookingUp = false; _notFound = true; });
      }
    });
  }

  void _onKey(int i, String val) {
    if (val.length > 1) {
      final clean = val.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      for (int j = 0; j < 6 && j < clean.length; j++) {
        _controllers[j].text = clean[j];
      }
      _focusNodes[5].requestFocus();
      _scheduleLookup(_code);
      return;
    }
    if (val.isNotEmpty && i < 5) {
      _focusNodes[i + 1].requestFocus();
    } else if (val.isEmpty && i > 0) {
      _focusNodes[i - 1].requestFocus();
      _controllers[i - 1].selection = TextSelection(baseOffset: 0, extentOffset: _controllers[i - 1].text.length);
    }
    _scheduleLookup(_code);
  }

  Future<void> _join() async {
    final l = context.read<L10n>();
    final code = _code;
    if (code.length < 6) {
      showToast(context, l.t('enter_6_chars'), error: true);
      return;
    }
    final provider = context.read<ClassesProvider>();
    setState(() => _busy = true);
    try {
      final cls = await provider.joinByCode(code);
      final id = cls['id'] as int;
      final title = cls['title'] ?? '';
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, '${l.t('joined_class')} $title');
      Navigator.pushNamed(context, '/class', arguments: id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final detail = (e is DioException && e.response?.data is Map) ? e.response?.data['detail'] : null;
      final key = detail == 'no_active_cohort'
          ? 'no_active_cohort'
          : detail == 'archived_rejoin_blocked'
              ? 'archived_rejoin_blocked'
              : 'not_found';
      showToast(context, l.t(key), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: Alignment.topRight,
          child: Tappable(onTap: () => Navigator.pop(context), label: 'Закрыть',
            child: Container(width: 30, height: 30, decoration: BoxDecoration(color: adaptiveSurface2(context), shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.xmark, size: 15, color: C.text4)))),
        const SizedBox(height: 2),
        Container(width: 60, height: 60,
          decoration: BoxDecoration(color: adaptiveSurface2(context), shape: BoxShape.circle),
          child: Icon(CupertinoIcons.lock_fill, color: adaptiveText1(context), size: 26)),
        const SizedBox(height: 16),
        Text(l.t('join_class_title'), textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: adaptiveText1(context))),
        const SizedBox(height: 8),
        Text(l.t('join_class_hint'), textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: adaptiveText3(context), height: 1.5)),
        const SizedBox(height: 24),

        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(6, (i) =>
          SizedBox(width: 44, height: 52, child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.backspace &&
                  _controllers[i].text.isEmpty && i > 0) {
                _controllers[i - 1].clear();
                _focusNodes[i - 1].requestFocus();
                _scheduleLookup(_code);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _controllers[i], focusNode: _focusNodes[i],
              textAlign: TextAlign.center, maxLength: i == 0 ? 6 : 1,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: adaptiveText1(context)),
              decoration: InputDecoration(
                counterText: '',
                filled: true, fillColor: adaptiveSurface2(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.tile), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.tile), borderSide: BorderSide(color: primary, width: 2)),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (val) => _onKey(i, val),
              onTap: () => _controllers[i].selection = TextSelection(baseOffset: 0, extentOffset: _controllers[i].text.length),
            ),
          )))),

        if (_lookingUp) Padding(padding: const EdgeInsets.only(top: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(l.t('checking_code'), style: TextStyle(fontSize: 13, color: adaptiveText3(context))),
          ])),

        if (!_lookingUp && _notFound) Padding(padding: const EdgeInsets.only(top: 16),
          child: Container(width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.red.withValues(alpha: isDark ? 0.16 : 0.08), borderRadius: BorderRadius.circular(AppRadii.tile)),
            child: Row(children: [
              const Icon(CupertinoIcons.exclamationmark_circle, size: 16, color: C.red),
              const SizedBox(width: 8),
              Expanded(child: Text(l.t('not_found'), style: const TextStyle(fontSize: 13, color: C.red, fontWeight: FontWeight.w500))),
            ]))),

        if (!_lookingUp && _foundClass != null) Padding(padding: const EdgeInsets.only(top: 16),
          child: Container(
            decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile), border: Border.all(color: adaptiveBorder(context))),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Builder(builder: (_) {
                final coverImg = cardCoverUrl(_foundClass!);
                return SizedBox(height: 80, width: double.infinity,
                  child: coverImg != null && coverImg.toString().startsWith('data:')
                      ? Builder(builder: (_) {
                          final bytes = decodeBase64Image(coverImg.toString());
                          return bytes != null
                              ? Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, gaplessPlayback: true, cacheWidth: 480)
                              : Container(color: adaptiveSurface2(context));
                        })
                      : coverImg != null
                          ? NetworkCoverImage(url: context.read<ApiService>().fixUrl(coverImg.toString()), memCacheWidth: 480,
                              errorBuilder: (_) => Container(color: adaptiveSurface2(context)))
                          : Container(color: adaptiveSurface2(context)));
              }),
              Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(CupertinoIcons.checkmark_circle_fill, size: 15, color: C.green),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_foundClass!['title'] ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                if ((_foundClass!['teacher_name'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3, left: 21),
                  child: Text(_foundClass!['teacher_name'], style: TextStyle(fontSize: 13, color: adaptiveText3(context), fontWeight: FontWeight.w600))),
              ])),
            ]))),

        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: AppButton.secondary(
            label: l.t('cancel'),
            onPressed: () => Navigator.pop(context),
          )),
          const SizedBox(width: 12),
          Expanded(child: AppButton.primary(
            label: l.t('join_enter_class'),
            loading: _busy,
            onPressed: _busy || _notFound ? null : _join,
          )),
        ]),
      ]);
  }
}
