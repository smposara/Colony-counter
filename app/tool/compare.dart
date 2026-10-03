// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:colony_counter/core/pipeline.dart';

/// Prints Dart vs Python vs true counts for the golden fixtures.
/// Run: dart run tool/compare.dart
void main() {
  for (final name in ['empty', 'sparse', 'medium', 'dense', 'backlit']) {
    final label = jsonDecode(
      File('test/fixtures/$name.json').readAsStringSync(),
    );
    final sw = Stopwatch()..start();
    final res = countPhoto(File('test/fixtures/$name.jpg').readAsBytesSync());
    print(
      '$name: true ${label['true_count']}, python ${label['python_count']}, '
      'dart ${res.count} (${sw.elapsedMilliseconds} ms) ${res.flags}',
    );
  }
}
