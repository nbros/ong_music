import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/ui/install_banner.dart';

void main() {
  test('the web manifest declares the Play app, without preferring it to the web app', () {
    final manifest = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map<String, Object?>;
    expect(manifest['related_applications'], [
      {'platform': 'play', 'url': playStoreUrl, 'id': 'nbros.ong_music'},
    ]);
    // true would stop Chrome on Android (and ChromeOS) from offering to install the web app
    expect(manifest['prefer_related_applications'], isFalse);
  });
}
