import 'dart:async';

/// Runs operations in order without letting a failed operation poison the queue.
class SerialQueue {
  Future<void>? _tail;

  Future<T> run<T>(Future<T> Function() operation) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;

    Future<T> execute() async {
      try {
        if (previous != null) await previous;
        return await operation();
      } finally {
        // An idle queue must not retain a future created in another clock/zone.
        // Clear it before completing the caller's result, including on failure.
        if (identical(_tail, done.future)) _tail = null;
        done.complete();
      }
    }

    return execute();
  }
}
