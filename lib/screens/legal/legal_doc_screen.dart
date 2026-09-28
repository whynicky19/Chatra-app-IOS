import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/inset_group.dart' show hairline;

/// Общий макет юридического документа (политика конфиденциальности, условия
/// использования): крупный заголовок в духе iOS, который сворачивается в
/// строку навигации при скролле, лид-абзац и список разделов.
class LegalDocScreen extends StatefulWidget {
  const LegalDocScreen({
    super.key,
    required this.titleKey,
    required this.headerIcon,
    required this.updated,
    required this.introKey,
    required this.sections,
  });

  final String titleKey;
  final IconData headerIcon;
  final String updated;
  final String introKey;

  /// (иконка, ключ заголовка, ключ текста) для каждой карточки.
  final List<(IconData, String, String)> sections;

  @override
  State<LegalDocScreen> createState() => _LegalDocScreenState();
}

class _LegalDocScreenState extends State<LegalDocScreen> {
  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final title = l.t(widget.titleKey);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return CupertinoTheme(
      data: AppTheme.cupertinoFor(theme),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackdrop(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              CupertinoSliverNavigationBar(
                backgroundColor:
                    theme.scaffoldBackgroundColor.withValues(alpha: 0.84),
                border: null,
                stretch: true,
                middle: Text(title),
                largeTitle:
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                leading: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(CupertinoIcons.chevron_left, size: 21),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + bottom),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Row(children: [
                      Icon(widget.headerIcon, size: 18, color: primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            '${l.t('pp_updated_label')}: ${widget.updated}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: adaptiveText3(context))),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    Text(l.t(widget.introKey),
                        style: TextStyle(
                            fontSize: 17,
                            height: 1.55,
                            letterSpacing: -0.2,
                            color: adaptiveTextSoft(context))),
                    const SizedBox(height: 30),
                    Text(l.t('sections').toUpperCase(),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            color: adaptiveText3(context))),
                    for (var i = 0; i < widget.sections.length; i++) ...[
                      const SizedBox(height: 22),
                      _section(context, primary, widget.sections[i]),
                      if (i != widget.sections.length - 1) ...[
                        const SizedBox(height: 22),
                        Container(
                            height: hairline(context),
                            color: adaptiveBorder(context)
                                .withValues(alpha: 0.55)),
                      ],
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(
      BuildContext context, Color primary, (IconData, String, String) section) {
    final l = context.read<L10n>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(section.$1, size: 18, color: primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(l.t(section.$2),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: adaptiveText1(context),
              )),
        ),
      ]),
      const SizedBox(height: 12),
      Text(l.t(section.$3),
          style: TextStyle(
            fontSize: 16,
            height: 1.6,
            letterSpacing: -0.2,
            color: adaptiveText2(context),
          )),
    ]);
  }
}
