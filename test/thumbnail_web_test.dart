// Browser only: flutter test --platform chrome test/thumbnail_web_test.dart
@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/ui/widgets.dart';

void main() {
  testWidgets('the web app builds the plain NetworkImage, which the browser\'s HTTP cache keeps', (tester) async {
    const url = 'https://i.ytimg.com/vi/abc/mqdefault.jpg';
    late ImageProvider image;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            image = ref.watch(thumbnailImageProvider)(url);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(image.runtimeType, NetworkImage(url).runtimeType);
    expect(image, NetworkImage(url));
  });
}
