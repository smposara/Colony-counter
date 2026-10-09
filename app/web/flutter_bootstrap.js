{{flutter_js}}
{{flutter_build_config}}

// No Flutter service worker: offline_sw.js (registered in index.html) keeps
// the app's files for offline use, and Flutter's own would remove it.
_flutter.loader.load();
