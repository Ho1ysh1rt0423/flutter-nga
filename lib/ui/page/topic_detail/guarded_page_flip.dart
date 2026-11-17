import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// 帖子详情页的翻页手势：横向幅度明显占优时才翻页。
///
/// 背景：TabBarView 默认的 PageScrollPhysics 里，横向识别器只要水平位移
/// 超过 18px 触摸斜率就接受手势——斜着滑动（比如边竖向滚动边带一点横向
/// 漂移）时经常先满足横向条件，列表还没滚就翻了页，非常容易误触。
///
/// 这里的判定改成两条同时满足才接受手势（真机手感调参）：
/// - 水平位移 ≥ [kFlipDragDistance]（48px，约为默认斜率的 2.6 倍）；
/// - 水平位移 > 纵向位移 × [dominanceRatio]（1.5，斜 45° 不翻）。
///
/// 接受手势后采用「过阈值翻页」而不是跟手拖动：TabBarView 内部自建
/// PageController，外部拿不到，跟手拖动只能整页换 PageView（改动太大）；
/// 过阈值 `animateTo` 的手感 NGA 网页版一致，疾挥（快速轻扫）也能翻。
///
/// 结构说明：TabBarView 传 [NeverScrollableScrollPhysics] 让内部不注册
/// 横向识别器（`Scrollable` 在 canDrag=false 时干脆不进手势竞技场，
/// 见 Scrollable._updateGestureRecognizers），外层 [RawGestureDetector]
/// 的自定义识别器才能赢到横向手势。原始位移由外层 [Listener] 统计
/// （Listener 不参与竞技场，竖向滚动照常工作）。
class GuardedPageFlip extends StatefulWidget {
  const GuardedPageFlip({
    required this.tabController,
    required this.child,
    super.key,
  });

  final TabController tabController;

  /// 通常是包了 NeverScrollableScrollPhysics 的 TabBarView。
  final Widget child;

  @override
  State<GuardedPageFlip> createState() => _GuardedPageFlipState();
}

/// 触发翻页的水平位移阈值（逻辑像素）。
const double kFlipDragDistance = 48;

/// 横向位移相对纵向位移需要占优的倍数。
const double kFlipDominanceRatio = 1.5;

/// 疾挥翻页的最小水平速度（逻辑像素/秒）。
const double kFlipFlingVelocity = 600;

class _GuardedPageFlipState extends State<GuardedPageFlip> {
  int? _activePointer;
  double _dx = 0;
  double _dy = 0;
  bool _flipTriggered = false;

  bool get _canFlipBack => widget.tabController.index > 0;
  bool get _canFlipForward =>
      widget.tabController.index < widget.tabController.length - 1;

  void _onPointerDown(PointerDownEvent event) {
    _activePointer = event.pointer;
    _dx = 0;
    _dy = 0;
    _flipTriggered = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _dx += event.delta.dx;
    _dy += event.delta.dy;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
  }

  /// 自定义识别器的接受判定：横向位移既要够远，又要明显大于纵向位移。
  bool _shouldAcceptDrag() {
    final dxAbs = _dx.abs();
    return dxAbs >= kFlipDragDistance && dxAbs > _dy.abs() * kFlipDominanceRatio;
  }

  void _flipTo(int index) {
    if (_flipTriggered) return;
    if (index < 0 || index > widget.tabController.length - 1) return;
    _flipTriggered = true;
    widget.tabController.animateTo(index);
  }

  void _onDragStart(DragStartDetails details) {
    // 识别器赢下竞技场时位移已过阈值，这里只挂个标记；
    // 真正的翻页在 update 里按累计位移触发。
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_flipTriggered) return;
    final dx = _dx;
    if (dx <= -kFlipDragDistance && _canFlipForward) {
      // 向左滑 → 下一页
      _flipTo(widget.tabController.index + 1);
    } else if (dx >= kFlipDragDistance && _canFlipBack) {
      // 向右滑 → 上一页
      _flipTo(widget.tabController.index - 1);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_flipTriggered) {
      _flipTriggered = false;
      return;
    }
    // 距离不够的快速轻扫也翻一页（判定仍要求横向占优）
    final velocity = details.velocity.pixelsPerSecond;
    if (velocity.dx.abs() < kFlipFlingVelocity) return;
    if (velocity.dx.abs() <= velocity.dy.abs() * kFlipDominanceRatio) return;
    if (velocity.dx < 0 && _canFlipForward) {
      _flipTo(widget.tabController.index + 1);
    } else if (velocity.dx > 0 && _canFlipBack) {
      _flipTo(widget.tabController.index - 1);
    }
  }

  void _onDragCancel() {
    _flipTriggered = false;
  }

  @override
  Widget build(BuildContext context) {
    // Listener 必须比 RawGestureDetector 更深：指针事件沿命中测试路径
    // 从叶子往根派发，Listener 先于识别器收到 move，识别器求值时才能
    // 读到最新的累计位移（外层的话会滞后一拍，单步拖动无法接受）。
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _HorizontalDominantDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _HorizontalDominantDragGestureRecognizer
            >(
              () => _HorizontalDominantDragGestureRecognizer(
                shouldAcceptDrag: _shouldAcceptDrag,
              ),
              (_HorizontalDominantDragGestureRecognizer instance) {
                instance
                  ..onStart = _onDragStart
                  ..onUpdate = _onDragUpdate
                  ..onEnd = _onDragEnd
                  ..onCancel = _onDragCancel;
              },
            ),
      },
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: widget.child,
      ),
    );
  }
}

/// 只在「横向幅度明显占优」时接受手势的水平拖动识别器。
///
/// 基类只按自身轴的累计位移判接受（没有占优判定），这里交给外层
/// [GuardedPageFlip] 用 Listener 统计的原始位移做判定。
class _HorizontalDominantDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  _HorizontalDominantDragGestureRecognizer({required this.shouldAcceptDrag});

  final bool Function() shouldAcceptDrag;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return shouldAcceptDrag();
  }
}
