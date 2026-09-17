import 'dart:async';

/// Exponential Backoff Reconnection Controller (1s, 2s, 4s).
class ReconnectController {
  static const List<Duration> defaultDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  final List<Duration> delays;
  final Future<bool> Function() onAttemptReconnect;
  final void Function() onMaxRetriesReached;

  int _retryCount = 0;
  Timer? _timer;
  bool _isReconnecting = false;
  int _generation = 0;

  ReconnectController({
    required this.onAttemptReconnect,
    required this.onMaxRetriesReached,
    this.delays = defaultDelays,
  });

  bool get isReconnecting => _isReconnecting;
  int get retryCount => _retryCount;

  void start() {
    cancel();
    _retryCount = 0;
    _isReconnecting = true;
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_retryCount >= delays.length) {
      _isReconnecting = false;
      onMaxRetriesReached();
      return;
    }

    final delay = delays[_retryCount];
    final generation = _generation;
    _timer = Timer(delay, () async {
      if (!_isReconnecting || generation != _generation) return;
      _retryCount++;
      final success = await onAttemptReconnect();
      if (!_isReconnecting || generation != _generation) return;
      if (success) {
        cancel();
      } else {
        _scheduleNext();
      }
    });
  }

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _isReconnecting = false;
    _retryCount = 0;
  }
}
