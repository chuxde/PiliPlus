import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart' show CupertinoRouteTransitionMixin;
import 'package:flutter/material.dart';

/// 澎湃OS风格视频转场：视频页从点击封面的矩形位置向下展开至全屏，
/// 内容随尺寸真实重排；返回时反向收回封面位置。
///
/// 未提供 [coverRect] 时回退为 cupertino 滑入。
class VideoExpandRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin {
  VideoExpandRoute({
    required this.builder,
    this.coverRect,
    this.expandDuration = const Duration(milliseconds: 450),
    super.settings,
  });

  final WidgetBuilder builder;
  final Rect? coverRect;
  final Duration expandDuration;

  @override
  Duration get transitionDuration =>
      coverRect == null ? const Duration(milliseconds: 400) : expandDuration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildContent(BuildContext context) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: builder(context),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final rect = coverRect;
    if (rect == null) {
      return super.buildTransitions(context, animation, secondaryAnimation, child);
    }
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) {
        final t = curved.value;
        final size = MediaQuery.sizeOf(context);
        return Stack(
          children: [
            Positioned(
              left: lerpDouble(rect.left, 0, t),
              top: lerpDouble(rect.top, 0, t),
              width: lerpDouble(rect.width, size.width, t),
              height: lerpDouble(rect.height, size.height, t),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(lerpDouble(12, 0, t)!),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
