import 'package:flutter/widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Сетевая обложка (класс/лекция) без отдельного compositing-слоя.
///
/// Раньше обложки рисовались виджетом CachedNetworkImage — он ради
/// fade-перехода оборачивает картинку в свой AnimatedSwitcher, то есть это
/// ОТДЕЛЬНЫЙ слой поверх фонового градиента-заглушки. Внутри ClipRRect со
/// скруглёнными углами два независимо антиалиасенных слоя иногда не совпадали
/// ровно по границе клипа на 1-2px — снаружи это выглядело как тонкая полоска
/// цвета фонового градиента у одного из краёв обложки. Голый Image с тем же
/// ImageProvider (тот же кэш, тот же cacheKey) красится одним слоем — щели
/// быть не может.
class NetworkCoverImage extends StatelessWidget {
  final String url;
  final String? cacheKey;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final int? memCacheWidth;
  final WidgetBuilder? placeholderBuilder;
  final WidgetBuilder? errorBuilder;

  const NetworkCoverImage({
    super.key,
    required this.url,
    this.cacheKey,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ResizeImage.resizeIfNeeded(
        memCacheWidth,
        null,
        CachedNetworkImageProvider(url, cacheKey: cacheKey),
      ),
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      errorBuilder: (ctx, _, __) =>
          (errorBuilder ?? placeholderBuilder)?.call(ctx) ?? const SizedBox.shrink(),
      frameBuilder: (ctx, child, frame, wasSyncLoaded) {
        if (frame == null && !wasSyncLoaded) {
          return placeholderBuilder?.call(ctx) ?? const SizedBox.shrink();
        }
        return child;
      },
    );
  }
}
