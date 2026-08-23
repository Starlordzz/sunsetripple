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
    _timer = Timer(delay, () async {
      _retryCount++;
      final success = await onAttemptReconnect();
      if (success) {
        cancel();
      } else {
        _scheduleNext();
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isReconnecting = false;
    _retryCount = 0;
  }
}
