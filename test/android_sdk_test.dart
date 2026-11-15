// The version of Android, read from the activity of the app (MainActivity.kt), for the confirmation of a copy.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/ui/actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nbros.ong_music/system');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<int?> read() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(androidSdkProvider.future);
  }

  test('the level the activity gives, asked once', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return 36;
    });
    expect(await read(), 36);
    expect(calls, ['sdkInt']);
    expect(systemPreviewsCopies(36), isTrue);
    expect(systemPreviewsCopies(33), isTrue);
    expect(systemPreviewsCopies(32), isFalse);
  });

  test('unknown when the activity cannot say: the message is shown', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'nope'));
    expect(await read(), isNull);
    expect(systemPreviewsCopies(null), isFalse);
  });

  test('not asked elsewhere than on Android', () async {
    var asked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked = true;
      return 36;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      expect(await read(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    expect(asked, isFalse);
  });
}
