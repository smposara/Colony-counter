import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:colony_counter/core/worker/protocol.dart';

@JS('self')
external JSObject get workerScope;
@JS('postMessage')
external void postResult(JSString message);

@JS()
extension type MessageEvent._(JSObject _) implements JSObject {
  external JSObject get data;
}

void main() {
  workerScope.setProperty(
    'onmessage'.toJS,
    ((MessageEvent event) {
      try {
        final payload = event.data;
        final job = jsonDecode(
          payload.getProperty<JSString>('json'.toJS).toDart,
        ) as Map<String, dynamic>;
        final bytes = payload.getProperty<JSUint8Array>('bytes'.toJS).toDart;
        final result = processPhotoJob(bytes, job);
        postResult(jsonEncode({'result': result}).toJS);
      } catch (error) {
        postResult(jsonEncode({'error': error.toString()}).toJS);
      }
    }).toJS,
  );
}
