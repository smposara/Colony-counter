import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('showSaveFilePicker')
external JSPromise<JSObject> pickFile(JSObject options);

@JS('Blob')
extension type ZipBlob._(JSObject _) implements JSObject {
  external factory ZipBlob(JSArray<JSAny> parts, JSObject options);
}

@JS('URL.createObjectURL')
external JSString objectUrl(JSObject blob);
@JS('URL.revokeObjectURL')
external void revokeUrl(JSString url);
@JS('document')
external JSObject get document;

/// How long a downloaded ZIP's Blob URL stays valid. iOS Safari reads it
/// only once the user confirms its "Download?" prompt.
const _keepUrl = Duration(minutes: 2);

/// Chrome desktop writes directly to disk. Other browsers assemble immutable
/// Blob parts, avoiding an aggregate Dart byte buffer and duplicate ZIP copy.
Future<void> deliverZip(
  Stream<Uint8List> chunks,
  String name,
  String subject,
) async {
  if (globalContext.hasProperty('showSaveFilePicker'.toJS).toDart) {
    final options = JSObject();
    options.setProperty('suggestedName'.toJS, name.toJS);
    final JSObject handle;
    try {
      handle = await pickFile(options).toDart;
    } catch (e) {
      if (e.toString().contains('AbortError')) return;
      rethrow;
    }
    final writer = await handle
        .callMethod<JSPromise<JSObject>>('createWritable'.toJS)
        .toDart;
    try {
      await for (final chunk in chunks) {
        await writer
            .callMethod<JSPromise<JSAny?>>('write'.toJS, chunk.toJS)
            .toDart;
      }
      await writer.callMethod<JSPromise<JSAny?>>('close'.toJS).toDart;
    } catch (_) {
      try {
        await writer.callMethod<JSPromise<JSAny?>>('abort'.toJS).toDart;
      } catch (_) {}
      rethrow;
    }
    return;
  }
  final options = JSObject();
  options.setProperty('type'.toJS, 'application/zip'.toJS);
  ZipBlob blob = ZipBlob(<JSAny>[].toJS, options);
  await for (final chunk in chunks) {
    blob = ZipBlob(<JSAny>[blob, chunk.toJS].toJS, options);
  }
  final url = objectUrl(blob);
  final anchor = document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
  anchor.setProperty('href'.toJS, url);
  anchor.setProperty('download'.toJS, name.toJS);
  final body = document.getProperty<JSObject>('body'.toJS);
  body.callMethod<JSAny?>('appendChild'.toJS, anchor);
  anchor.callMethod<JSAny?>('click'.toJS);
  anchor.callMethod<JSAny?>('remove'.toJS);
  // Keep the URL alive until the browser has read the download (not awaited:
  // the export is done for the app).
  Timer(_keepUrl, () => revokeUrl(url));
}
