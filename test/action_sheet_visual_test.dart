import 'package:chatra_app/screens/classes/widgets/viewer_action_sheet.dart';
import 'package:chatra_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app action sheet golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: const Color(0xFF3A3A3E),
        body: Builder(
          builder: (ctx) => Center(
            child: FilledButton(
              onPressed: () => showAppActionSheet(
                ctx,
                title: 'Laboratory work No 1 (1).docx',
                cancelLabel: 'Отмена',
                actions: [
                  AppActionSheetAction(
                    icon: Icons.bookmark_border,
                    label: 'Мои выделения',
                    onTap: _noop,
                  ),
                  AppActionSheetAction(
                    icon: Icons.grid_view_outlined,
                    label: 'Страницы',
                    onTap: _noop,
                  ),
                  AppActionSheetAction(
                    icon: Icons.delete_outline,
                    label: 'Удалить',
                    destructive: true,
                    onTap: _noop,
                  ),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/action_sheet.png'),
    );
  });
}

void _noop() {}
