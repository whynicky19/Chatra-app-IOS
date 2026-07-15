import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Официальный логотип Telegram (синий круг с белым самолётиком).
///
/// Путь — стандартный 24×24 глиф: он рисует круг, а самолётик остаётся
/// «дыркой» за счёт обратного направления обхода. Поэтому под ним лежит белый
/// круг — сквозь дырку видно именно его, а сам путь залит фирменным градиентом.
class TelegramLogo extends StatelessWidget {
  final double size;
  const TelegramLogo({super.key, this.size = 24});

  static const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <defs>
    <linearGradient id="tg" x1="12" y1="0" x2="12" y2="24" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#2AABEE"/>
      <stop offset="1" stop-color="#229ED9"/>
    </linearGradient>
  </defs>
  <circle cx="12" cy="12" r="12" fill="#FFFFFF"/>
  <path fill="url(#tg)" d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.009-1.252-.242-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/>
</svg>
''';

  @override
  Widget build(BuildContext context) =>
    SvgPicture.string(_svg, width: size, height: size);
}
