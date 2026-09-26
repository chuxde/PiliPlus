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
      // 默认飞行使用目标侧的 child（这里是播放器，未初始化时是黑块），
      // 改为始终显示列表侧卡片封面，视觉上即封面展开。
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
        return (hero as Hero).child;
      },
      child: child,
    );
  }
}
