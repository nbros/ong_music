import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Android app opts into predictive back: the system previews where Back leads', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest)!.group(0)!;
    expect(application, contains('android:enableOnBackInvokedCallback="true"'));
  });
}
