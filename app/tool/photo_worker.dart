import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:colony_counter/core/worker/protocol.dart';

@JS('self')
external JSObject get workerScope;
@JS('postMessage')
external void postResult(JSAny message, JSArray<JSAny> transfer);

void respond(Map<String, dynamic> response, [Uint8List? bytes]) {
  final payload = JSObject();
  payload.setProperty('json'.toJS, jsonEncode(response).toJS);
  final transfer = <JSAny>[];
  if (bytes != null) {
    final data = bytes.toJS;
    payload.setProperty('bytes'.toJS, data);
    transfer.add(data.getProperty<JSArrayBuffer>('buffer'.toJS));
  }
  postResult(payload, transfer.toJS);
}

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
        final binary = result.remove('binary') as Uint8List?;
        respond({'result': result}, binary);
      } catch (error) {
        respond({'error': error.toString()});
      }
    }).toJS,
  );
}
