import 'dart:async';
import 'package:flutter/widgets.dart';
import 'live_vehicles_service.dart';

/// The single worker that keeps live bus positions coming.
///
/// One poll serves every screen. The feed has no per-route endpoint, so each
/// refresh pulls the whole fleet (~830 KB) straight from TransMilenio to
/// this phone - there is no server of ours in between. Polling it once per
/// interval and fanning the result out is the only lever we have on that
/// cost, which is why nothing here polls on its own.
///
/// It runs only while something is listening and the app is on screen, and
/// stops the moment the last screen looks away.
class LiveVehiclesFeed {
  /// Matches how often the agency republishes.
  static const refreshInterval = Duration(seconds: 15);

  static final LiveVehiclesFeed instance = LiveVehiclesFeed._();

  LiveVehiclesFeed._() {
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _sync();
      },
    );
  }

  late final AppLifecycleListener _lifecycle;
  final _controller = StreamController<List<LiveVehicle>>.broadcast();

  Timer? _timer;
  int _listeners = 0;
  bool _foreground = true;
  List<LiveVehicle> _latest = const [];
  DateTime? _updatedAt;

  /// True while a refresh is in flight. Screens use it to say "buscando
  /// buses" if the wait is long enough to be noticed.
  final ValueNotifier<bool> fetching = ValueNotifier(false);

  /// What the last refresh returned, for a screen that has just attached and
  /// should not wait 15 s to draw anything.
  List<LiveVehicle> get latest => _latest;

  DateTime? get updatedAt => _updatedAt;

  bool get isRunning => _timer != null;

  /// Subscribes to the worker, starting it if this is the first listener.
  /// Cancelling the returned subscription releases it.
  StreamSubscription<List<LiveVehicle>> subscribe(
    void Function(List<LiveVehicle> vehicles) onData,
  ) {
    _listeners++;
    _sync();
    if (_latest.isNotEmpty) {
      // Draw what we already have before the next tick.
      scheduleMicrotask(() => onData(_latest));
    }
    return _CountedSubscription(_controller.stream.listen(onData), _release);
  }

  void _release() {
    _listeners = _listeners > 0 ? _listeners - 1 : 0;
    _sync();
  }

  void _sync() {
    final shouldRun =
        _listeners > 0 && _foreground && LiveVehiclesService.enabled;
    if (shouldRun && _timer == null) {
      _tick();
      _timer = Timer.periodic(refreshInterval, (_) => _tick());
    } else if (!shouldRun && _timer != null) {
      _timer!.cancel();
      _timer = null;
      fetching.value = false;
    }
  }

  /// Called when the setting is toggled, so the worker starts or stops
  /// without waiting for a screen change.
  void settingChanged() => _sync();

  Future<void> _tick() async {
    fetching.value = true;
    try {
      final vehicles = await LiveVehiclesService.fetchAll();
      _latest = vehicles;
      if (vehicles.isNotEmpty) _updatedAt = DateTime.now();
      if (!_controller.isClosed) _controller.add(vehicles);
    } finally {
      fetching.value = false;
    }
  }

  @visibleForTesting
  void debugDispose() {
    _timer?.cancel();
    _timer = null;
    _lifecycle.dispose();
    _controller.close();
  }
}

/// Releases the feed's listener count when the screen cancels.
class _CountedSubscription<T> implements StreamSubscription<T> {
  final StreamSubscription<T> _inner;
  final void Function() _onCancel;
  bool _cancelled = false;

  _CountedSubscription(this._inner, this._onCancel);

  @override
  Future<void> cancel() {
    if (!_cancelled) {
      _cancelled = true;
      _onCancel();
    }
    return _inner.cancel();
  }

  @override
  void onData(void Function(T)? handleData) => _inner.onData(handleData);
  @override
  void onError(Function? handleError) => _inner.onError(handleError);
  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);
  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);
  @override
  void resume() => _inner.resume();
  @override
  bool get isPaused => _inner.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);
}
