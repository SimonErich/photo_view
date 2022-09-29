import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'photo_view_hit_corners.dart';

class PhotoViewGestureDetector extends StatelessWidget {
  const PhotoViewGestureDetector({
    Key? key,
    this.hitDetector,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.onDoubleTap,
    this.child,
    this.onTapUp,
    this.onTapDown,
    this.behavior,
  }) : super(key: key);

  final GestureDoubleTapCallback? onDoubleTap;
  final HitCornersDetector? hitDetector;

  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

  final GestureTapUpCallback? onTapUp;
  final GestureTapDownCallback? onTapDown;

  final Widget? child;

  final HitTestBehavior? behavior;

  @override
  Widget build(BuildContext context) {
    final scope = PhotoViewGestureDetectorScope.of(context);

    final Axis? axis = scope?.axis;
    final touchSlopFactor = scope?.touchSlopFactor ?? 2;

    final Map<Type, GestureRecognizerFactory> gestures =
        <Type, GestureRecognizerFactory>{};

    if (onTapDown != null || onTapUp != null) {
      gestures[TapGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(debugOwner: this),
        (TapGestureRecognizer instance) {
          instance
            ..onTapDown = onTapDown
            ..onTapUp = onTapUp;
        },
      );
    }

    gestures[DoubleTapGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
      () => DoubleTapGestureRecognizer(debugOwner: this),
      (DoubleTapGestureRecognizer instance) {
        instance..onDoubleTap = onDoubleTap;
      },
    );

    gestures[PhotoViewGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<PhotoViewGestureRecognizer>(
      () => PhotoViewGestureRecognizer(
          hitDetector: hitDetector,
          debugOwner: this,
          validateAxis: axis,
          touchSlopFactor: touchSlopFactor),
      (PhotoViewGestureRecognizer instance) {
        instance
          ..onStart = onScaleStart
          ..onUpdate = onScaleUpdate
          ..onEnd = onScaleEnd;
      },
    );

    return RawGestureDetector(
      behavior: behavior,
      child: child,
      gestures: gestures,
    );
  }
}

class PhotoViewGestureRecognizer extends ScaleGestureRecognizer {
  PhotoViewGestureRecognizer({
    this.hitDetector,
    Object? debugOwner,
    this.validateAxis,
    this.touchSlopFactor = 2,
    PointerDeviceKind? kind,
  }) : super(debugOwner: debugOwner);
  final HitCornersDetector? hitDetector;
  final Axis? validateAxis;
  final double touchSlopFactor;

  Map<int, Offset> _pointerLocations = <int, Offset>{};

  Offset? _initialFocalPoint;
  Offset? _currentFocalPoint;
  double? _initialSpan;
  double? _currentSpan;

  bool ready = true;

  @override
  void addAllowedPointer(event) {
    if (ready) {
      ready = false;
      _pointerLocations = <int, Offset>{};
    }
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    ready = true;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (validateAxis != null) {
      bool didChangeConfiguration = false;
      if (event is PointerMoveEvent) {
        if (!event.synthesized) {
          _pointerLocations[event.pointer] = event.position;
        }
      } else if (event is PointerDownEvent) {
        _pointerLocations[event.pointer] = event.position;
        didChangeConfiguration = true;
      } else if (event is PointerUpEvent || event is PointerCancelEvent) {
        _pointerLocations.remove(event.pointer);
        didChangeConfiguration = true;
      }

      _updateDistances();

      if (didChangeConfiguration) {
        // cf super._reconfigure
        _initialFocalPoint = _currentFocalPoint;
        _initialSpan = _currentSpan;
      }

      _decideIfWeAcceptEvent(event);
    }
    super.handleEvent(event);
  }

  void _computeEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (!event.synthesized) {
        _pointerLocations[event.pointer] = event.position;
      }
    } else if (event is PointerDownEvent) {
      _pointerLocations[event.pointer] = event.position;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointerLocations.remove(event.pointer);
    }

    _initialFocalPoint = _currentFocalPoint;
  }

  void _updateDistances() {
    // cf super._update
    final int count = _pointerLocations.keys.length;

    // Compute the focal point
    Offset focalPoint = Offset.zero;
    for (final int pointer in _pointerLocations.keys)
      focalPoint += _pointerLocations[pointer]!;
    _currentFocalPoint =
        count > 0 ? focalPoint / count.toDouble() : Offset.zero;

    // Span is the average deviation from focal point. Horizontal and vertical
    // spans are the average deviations from the focal point's horizontal and
    // vertical coordinates, respectively.
    double totalDeviation = 0.0;
    for (final int pointer in _pointerLocations.keys) {
      totalDeviation +=
          (_currentFocalPoint! - _pointerLocations[pointer]!).distance;
    }
    _currentSpan = count > 0 ? totalDeviation / count : 0.0;
  }

  void _decideIfWeAcceptEvent(PointerEvent event) {
    if (!(event is PointerMoveEvent)) {
      return;
    }
    final move = _initialFocalPoint! - _currentFocalPoint!;
    final bool shouldMove = validateAxis == Axis.vertical
        ? hitDetector!.shouldMove(move, Axis.vertical)
        : hitDetector!.shouldMove(move, Axis.horizontal);
    if (shouldMove || _pointerLocations.keys.length > 1) {
      final double spanDelta = (_currentSpan! - _initialSpan!).abs();
      final double focalPointDelta =
          (_currentFocalPoint! - _initialFocalPoint!).distance;
      // warning: do not compare `focalPointDelta` to `kPanSlop`
      // `ScaleGestureRecognizer` uses `kPanSlop`, but `HorizontalDragGestureRecognizer` uses `kTouchSlop`
      // and PhotoView recognizer may compete with the `HorizontalDragGestureRecognizer` from a containing `PageView`
      // setting `touchSlopFactor` to 2 restores default `ScaleGestureRecognizer` behaviour as `kPanSlop = kTouchSlop * 2.0`
      // setting `touchSlopFactor` in [0, 1] will allow this recognizer to accept the gesture before the one from `PageView`
      if (spanDelta > kScaleSlop ||
          focalPointDelta > kTouchSlop * touchSlopFactor) {
        acceptGesture(event.pointer);
      }
    }
  }
}

/// An [InheritedWidget] responsible to give a axis aware scope to [PhotoViewGestureRecognizer].
///
/// When using this, PhotoView will test if the content zoomed has hit edge every time user pinches,
/// if so, it will let parent gesture detectors win the gesture arena
///
/// Useful when placing PhotoView inside a gesture sensitive context,
/// such as [PageView], [Dismissible], [BottomSheet].
///
/// Usage example:
/// ```
/// PhotoViewGestureDetectorScope(
///   axis: Axis.vertical,
///   child: PhotoView(
///     imageProvider: AssetImage("assets/pudim.jpg"),
///   ),
/// );
/// ```
class PhotoViewGestureDetectorScope extends InheritedWidget {
  PhotoViewGestureDetectorScope({
    this.axis,
    this.touchSlopFactor = .8,
    required Widget child,
  }) : super(child: child);

  static PhotoViewGestureDetectorScope? of(BuildContext context) {
    final PhotoViewGestureDetectorScope? scope = context
        .dependOnInheritedWidgetOfExactType<PhotoViewGestureDetectorScope>();
    return scope;
  }

  final Axis? axis;

  // in [0, 1[
  // 0: most reactive but will not let tap recognizers accept gestures
  // <1: less reactive but gives the most leeway to other recognizers
  // 1: will not be able to compete with a `HorizontalDragGestureRecognizer` up the widget tree
  final double touchSlopFactor;  

  @override
  bool updateShouldNotify(PhotoViewGestureDetectorScope oldWidget) {
    return axis != oldWidget.axis &&
        touchSlopFactor != oldWidget.touchSlopFactor;
  }
}

// `PageView` contains a `Scrollable` which sets up a `HorizontalDragGestureRecognizer`
// this recognizer will win in the gesture arena when the drag distance reaches `kTouchSlop`
// we cannot change that, but we can prevent the scrollable from panning until this threshold is reached
// and let other recognizers accept the gesture instead
class PhotoViewPageViewScrollPhysics extends ScrollPhysics {
  const PhotoViewPageViewScrollPhysics({
    this.touchSlopFactor = 1,
    ScrollPhysics? parent,
  }) : super(parent: parent);

  // in [0, 1]
  // 0: most reactive but will not let PhotoView recognizers accept gestures
  // 1: less reactive but gives the most leeway to PhotoView recognizers
  final double touchSlopFactor;

  @override
  PhotoViewPageViewScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PhotoViewPageViewScrollPhysics(
      touchSlopFactor: touchSlopFactor,
      parent: buildParent(ancestor),
    );
  }

  @override
  double get dragStartDistanceMotionThreshold => kTouchSlop * touchSlopFactor;
}
