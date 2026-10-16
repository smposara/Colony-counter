import 'package:colony_counter/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  chapter('count', (m) async {
    await m.start();
    await m.shot('1-home', [(find.text(tr.homeCountPlate), Mark.tap)]);
    nextPhoto = fixture('medium.jpg');
    await m.tap(find.text(tr.homeCountPlate));
    await m.shot('2-review', [(find.text(tr.reviewModeEdit), Mark.tap)]);
  });
}
