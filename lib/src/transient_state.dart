import 'package:flutter_riverpod/flutter_riverpod.dart';

class IntOptionNotifier extends StateNotifier<int> {
  IntOptionNotifier(super.initialState);

  set value(int value) {
    state = value;
  }

  int get value => state;
}

typedef CurrentPageNotifier = IntOptionNotifier;
final currentPageProvider = StateNotifierProvider<CurrentPageNotifier, int>((ref) => CurrentPageNotifier(0));
