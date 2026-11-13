/// The history of the browser's tab, as the web app needs it beyond what
/// Flutter's engine offers: where it is, and moving in it. The browser side is
/// `browserHistory()` (web platform); the native apps have none.
library;

/// The history of the tab the web app runs in.
abstract interface class BrowserHistory {
  /// The step on screen: its place among the app's steps (0 for the first
  /// one, counted by the engine), and how many things open over the page it
  /// stands for (0 for a step of a tab and its search).
  ({int position, int over}) get current;

  /// Moves [delta] steps (negative: back), as the browser's buttons do. The
  /// browser tells the app when it gets there, a moment later, as it does for
  /// its own buttons.
  void go(int delta);
}

/// How many things open over the page the step of [state] stands for: the
/// state the app gives its steps (`{'over': n}`), as it comes back from the
/// browser; 0 for anything else.
int overOfState(Object? state) => switch (state) {
  {'over': final num over} => over.toInt(),
  _ => 0,
};
