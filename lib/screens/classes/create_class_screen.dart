import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/cover_art.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/cover_appearance.dart';
import '../../widgets/toast.dart';

/// Полноэкранная форма создания класса — раньше была модальным `Dialog`
/// фиксированной высоты, где длинное описание или клавиатура обрезали форму.
/// Здесь, как и в lecture_editor_screen.dart, `PopScope` не даёт случайно
/// закрыть уже заполненную форму.
class CreateClassScreen extends StatefulWidget {
  const CreateClassScreen({super.key});

  @override
  State<CreateClassScreen> createState() => _CreateClassScreenState();
}

class _CreateClassScreenState extends State<CreateClassScreen> {
  final _nameC = TextEditingController();
  final _descC = TextEditingController();
  final _teacherC = TextEditingController();
  final _periodC = TextEditingController();
  bool _submitting = false;
  bool _dirty = false;

  String _coverColor = kFallbackCoverOptions.defaultColor;
  String _coverIcon = kFallbackCoverOptions.defaultIcon;

  /// Предмет, созданный на первом шаге. Пока null — экран на шаге ввода
  /// данных; как только появился, экран переключается на работу с обложкой.
  Map<String, dynamic>? _created;
  bool _generating = false;
  String? _coverError;

  @override
  void dispose() {
    _nameC.dispose();
    _descC.dispose();
    _teacherC.dispose();
    _periodC.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<bool> _confirmDiscard() async {
    // Предмет уже сохранён на сервере (вместе с обложкой) — терять нечего,
    // спрашивать «отменить изменения?» на этом шаге было бы враньём.
    if (_created != null) return !_generating;
    if (!_dirty) return true;
    final l = context.read<L10n>();
    final ok = await showConfirmDialog(
      context,
      title: l.t('discard_changes_title'),
      message: l.t('discard_changes_msg'),
      danger: true,
      confirmText: l.t('discard_changes_confirm'),
      cancelText: l.t('cancel'),
    );
    return ok == true;
  }

  Future<void> _submit() async {
    final l = context.read<L10n>();
    if (_nameC.text.trim().isEmpty) {
      showToast(context, l.t('enter_class_name'), error: true);
      return;
    }
    setState(() => _submitting = true);
    final api = context.read<ApiService>();
    try {
      final created = await api.createClass(_nameC.text.trim(),
          description: _descC.text.trim(),
          teacher: _teacherC.text.trim(),
          period: _periodC.text.trim(),
          coverColor: _coverColor,
          coverIcon: _coverIcon);
      if (!mounted) return;
      _dirty = false;
      showToast(context, l.t('class_created'));
      setState(() {
        _created = created;
        _submitting = false;
      });
      // Первую генерацию запускаем сами — для пользователя это продолжение
      // нажатия «Создать», а не отдельное непонятное действие. Предмет уже
      // сохранён с обложкой-фолбэком, поэтому её сбой ничего не ломает.
      _generateCover();
    } catch (e) {
      if (!mounted) return;
      final detail = (e is DioException && e.response?.data is Map) ? e.response?.data['detail'] : null;
      showToast(context, detail?.toString() ?? l.t('error'), error: true);
      setState(() => _submitting = false);
    }
  }

  Future<void> _generateCover() async {
    final created = _created;
    if (created == null || _generating) return;   // защита от двойного нажатия
    final l = context.read<L10n>();
    final api = context.read<ApiService>();
    setState(() {
      _generating = true;
      _coverError = null;
    });
    try {
      final res = await api.generateClassCover(
        (created['id'] as num).toInt(),
        color: _coverColor,
        icon: _coverIcon,
      );
      if (!mounted) return;
      setState(() => _created = {...created, ...res});
    } catch (e) {
      if (!mounted) return;
      final detail = (e is DioException && e.response?.data is Map) ? e.response?.data['detail'] : null;
      setState(() => _coverError = detail == 'too_many_cover_generations'
          ? l.t('cover_rate_limited')
          : l.t('cover_generate_failed'));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: isDark ? C.darkBg : C.bg,
        body: Stack(children: [
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 20, 4),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark, size: 20),
                    tooltip: 'Закрыть',
                    onPressed: () async {
                      if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
                    },
                  ),
                  Expanded(child: Text(
                    _created == null ? l.t('create_class_title') : l.t('cover_appearance'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: adaptiveText1(context)))),
                  const SizedBox(width: 40),
                ]),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 28),
                  children: [
                    CoverAppearance(
                      color: _coverColor,
                      icon: _coverIcon,
                      coverUrl: _created?['cover_image'] as String?,
                      coverSource: _created?['cover_source'] as String?,
                      classId: (_created?['id'] as num?)?.toInt(),
                      generating: _generating,
                      error: _coverError,
                      onColorChanged: (v) { setState(() => _coverColor = v); _markDirty(); },
                      onIconChanged: (v) { setState(() => _coverIcon = v); _markDirty(); },
                      onGenerate: _generateCover,
                    ),
                    const SizedBox(height: 28),

                    // Поля предмета скрываются после создания: на втором шаге
                    // экран занимается только обложкой, и лишние поля отвлекали бы.
                    if (_created == null) ..._classFields(l),

                    if (_created == null)
                      AppButton.primary(
                        label: l.t('create'),
                        icon: CupertinoIcons.plus,
                        color: primary,
                        loading: _submitting,
                        onPressed: _submitting ? null : _submit,
                        glow: true,
                        minHeight: 52,
                      )
                    else
                      // Предмет уже сохранён, поэтому это просто «закрыть»:
                      // обложка есть в любом случае, даже если генерацию не
                      // запускали или она не удалась.
                      AppButton.primary(
                        label: l.t('done'),
                        icon: CupertinoIcons.check_mark,
                        color: primary,
                        onPressed: _generating ? null : () => Navigator.pop(context, _created),
                        glow: true,
                        minHeight: 52,
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _classFields(L10n l) => [
                    _label('${l.t('class_name_required')} *'),
                    TextField(
                      controller: _nameC,
                      decoration: InputDecoration(hintText: l.t('class_name_hint')),
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 18),

                    _label(l.t('class_desc')),
                    TextField(
                      controller: _descC,
                      decoration: InputDecoration(hintText: l.t('class_desc_hint')),
                      maxLines: 3,
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 18),

                    // Подписи и поля лежат в двух отдельных Row (а не парами
                    // внутри своих Column), чтобы разная длина слова
                    // "Период"/"Учитель" в разных языках не сдвигала поля
                    // ввода друг относительно друга по высоте — Row всегда
                    // берёт высоту самой высокой подписи для обеих колонок.
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _label(l.t('period_label'))),
                      const SizedBox(width: 14),
                      Expanded(child: _label(l.t('teacher_label'))),
                    ]),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: TextField(
                        controller: _periodC,
                        decoration: InputDecoration(hintText: l.t('period_hint')),
                        onChanged: (_) => _markDirty(),
                      )),
                      const SizedBox(width: 14),
                      Expanded(child: TextField(
                        controller: _teacherC,
                        decoration: InputDecoration(hintText: l.t('your_name_hint')),
                        onChanged: (_) => _markDirty(),
                      )),
                    ]),
                    const SizedBox(height: 32),
      ];

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text3)),
      );
}
