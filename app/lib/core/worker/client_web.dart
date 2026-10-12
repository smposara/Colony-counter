import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('Worker')
extension type PhotoWorker._(JSObject _) implements JSObject {
  external factory PhotoWorker(JSString url);
  external set onmessage(JSFunction callback);
  external set onerror(JSFunction callback);
  external set onmessageerror(JSFunction callback);
  external void postMessage(JSAny message, JSArray<JSAny> transfer);
  external void terminate();
}

@JS()
extension type WorkerMessage._(JSObject _) implements JSObject {
  external JSAny? get data;
}

/// A worker per job keeps detector buffers isolated and releases them on finish.
/// Transferring a copy leaves the original photo usable for review and saving.
Future<Map<String, dynamic>> runPhotoJob(
  Uint8List bytes,
  Map<String, dynamic> job,
) async {
  final worker = PhotoWorker('photo_worker.dart.js'.toJS);
  final result = Completer<Map<String, dynamic>>();
  final timer = Timer(const Duration(minutes: 2), () {
    if (!result.isCompleted) {
      result.completeError(
        TimeoutException('Photo analysis timed out. Try a smaller photo.'),
      );
    }
  });
  worker.onmessage = ((WorkerMessage event) {
    if (result.isCompleted) return;
    try {
      final response =
          jsonDecode((event.data as JSString).toDart) as Map<String, dynamic>;
      if (response['error'] != null) {
        result.completeError(StateError(response['error'] as String));
      } else {
        result.complete((response['result'] as Map).cast<String, dynamic>());
      }
    } catch (e, stack) {
      result.completeError(e, stack);
    }
  }).toJS;
  void failed(JSAny? _) {
    if (!result.isCompleted) {
      result.completeError(
        StateError('Photo worker unavailable. Reload the app and try again.'),
      );
    }
  }

  worker.onerror = failed.toJS;
  worker.onmessageerror = failed.toJS;
  try {
    final copy = Uint8List.fromList(bytes).toJS;
    final message = JSObject();
    message.setProperty('json'.toJS, jsonEncode(job).toJS);
    message.setProperty('bytes'.toJS, copy);
    worker.postMessage(
      message,
      <JSAny>[copy.getProperty<JSArrayBuffer>('buffer'.toJS)].toJS,
    );
    return await result.future;
  } finally {
    timer.cancel();
    worker.terminate();
  }
}
