import 'package:chatra_app/models/annotation.dart';
import 'package:chatra_app/screens/classes/widgets/highlight_menu.dart'
    show HighlightMenu, HighlightMenuDock;
import 'package:chatra_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('highlight menu golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: const Color(0xFF3A3A3E),
        body: Align(
          alignment: Alignment.bottomCenter,
          child: HighlightMenuDock(
            visible: true,
            child: HighlightMenu(
              t: (k) => k,
              existing: const Annotation(
                id: 1,
                lectureId: 1,
                classId: 1,
                fileIndex: -1,
                page: 1,
                selectedText: 'selected fragment',
                prefix: '',
                suffix: '',
                startOffset: 0,
                endOffset: 17,
                color: 'yellow',
              ),
              onColor: (_) {},
              onNote: () {},
              onAskAi: () {},
              onCopy: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/highlight_menu.png'),
    );
  });
}
