import 'package:flutter/widgets.dart';

import 'package:PiliPlus/utils/storage_pref.dart';

/// 澎湃OS风格视频转场：封面从点击位置飞入/飞出播放器区域。
///
/// 仅当「页面过渡动画」选择 videoExpand 时生效，否则原样返回 child，
/// 对现有行为零影响。tag 由调用方生成并保证列表侧与视频页侧一致。
class VideoCoverHero extends StatelessWidget {
  const VideoCoverHero({super.key, required this.tag, required this.child});

  final Object? tag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Pref.isVideoExpandTransition || tag == null) {
      return child;
    }
    return Hero(
      tag: tag!,
      createRectTween: createCoverRectTween,
      // 默认飞行使用目标侧的 child（这里是播放器，未初始化时是黑块），
      // 改为始终显示列表侧卡片封面；FittedBox 保证封面在矩形插值
      // 过程中不被拉伸变形（正常情况下 tween 已保持封面宽高比，此为兜底）。
      // push 末段淡出，让封面渐隐融入播放器，避免落点生硬；pop 保持不透明。
      flightShuttleBuilder: (
        BuildContext flightContext,
        Animation<double> animation,
        HeroFlightDirection flightDirection,
        BuildContext fromHeroContext,
        BuildContext toHeroContext,
      ) {
        final hero = flightDirection == HeroFlightDirection.push
            ? fromHeroContext.widget
            : toHeroContext.widget;
        Widget shuttle = FittedBox(fit: BoxFit.contain, child: (hero as Hero).child);
        if (flightDirection == HeroFlightDirection.push) {
          shuttle = FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.7, 1, curve: Curves.easeIn),
              ),
            ),
            child: shuttle,
          );
        }
        return shuttle;
      },
      child: child,
    );
  }
}

/// 飞行矩形插值：播放器矩形按封面（较小一侧）的宽高比 contain 适配，
/// 起止矩形宽高比一致，飞行全程为纯缩放+平移，封面不变形。
RectTween createCoverRectTween(Rect? from, Rect? to) {
  if (from == null || to == null) {
    return RectTween(begin: from, end: to);
  }
  // 封面卡片必然小于播放器区域，以此区分两侧矩形
  final isCoverFrom = from.width * from.height <= to.width * to.height;
  final cover = isCoverFrom ? from : to;
  final other = isCoverFrom ? to : from;
  final ratio = cover.width / cover.height;
  double width = other.width;
  double height = width / ratio;
  if (height > other.height) {
    height = other.height;
    width = height * ratio;
  }
  final fitted = Rect.fromCenter(
    center: other.center,
    width: width,
    height: height,
  );
  return RectTween(begin: isCoverFrom ? from : fitted, end: isCoverFrom ? fitted : to);
}
