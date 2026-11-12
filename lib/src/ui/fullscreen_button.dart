/// The full screen button beside the search fields, in the browser only.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../web/fullscreen.dart';
import '../web/web_platform.dart';
import 'actions.dart';

/// The browser's full screen mode of the page; null where there is none to
/// offer: native apps, iPhone, installed web app, browsers without the
/// Fullscreen API. Overridden in tests.
final pageFullscreenProvider = Provider<PageFullscreen?>((ref) => pageFullscreen());

/// Shows the page full screen, or leaves full screen.
///
/// The icon follows the browser, which the user can also leave full screen
/// with (Escape, its own gesture); it changes in place, at one size. For screen
/// readers: a "Full screen" switch, on or off.
class FullscreenButton extends StatelessWidget {
  const FullscreenButton({super.key, required this.fullscreen});

  final PageFullscreen fullscreen;

  void _toggle(BuildContext context) {
    if (fullscreen.isFullscreen.value) {
      fullscreen.exit();
      return;
    }
    // called right away: the browser grants full screen only within the tap
    fullscreen.enter().then((accepted) {
      // not when the page is full screen all the same: a second tap while the browser was still granting the first
      if (!accepted && !fullscreen.isFullscreen.value && context.mounted) {
        showMessage(context, 'Couldn’t go full screen');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ValueListenableBuilder<bool>(
      valueListenable: fullscreen.isFullscreen,
      builder: (context, on, _) => Semantics(
        container: true,
        button: true,
        toggled: on,
        label: 'Full screen',
        onTap: () => _toggle(context),
        // one label whatever the state, which the switch tells
        excludeSemantics: true,
        child: IconButton(
          tooltip: on ? 'Exit full screen' : 'Full screen',
          onPressed: () => _toggle(context),
          icon: Icon(on ? Icons.fullscreen_exit : Icons.fullscreen, color: color),
        ),
      ),
    );
  }
}
