package nbros.ong_music

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // A shortcut of the launcher icon comes as an extra of the intent that started the activity, which the
        // quick_actions plugin reads when the app starts (lib/src/ui/launcher_shortcuts.dart). Started again from
        // Recents after its process died, the activity gets that same intent back: the shortcut was used then, not
        // now. Before super.onCreate, which hands the intent to the plugin.
        val fromHistory = (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (fromHistory || savedInstanceState != null) intent.removeExtra(QUICK_ACTION_EXTRA)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The version of Android, for what depends on it in the app (androidSdkProvider, lib/src/ui/actions.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nbros.ong_music/system").setMethodCallHandler {
            call,
            result ->
            if (call.method == "sdkInt") result.success(Build.VERSION.SDK_INT) else result.notImplemented()
        }
    }

    private companion object {
        // The extra the quick_actions plugin puts the shortcut in (QuickActions.EXTRA_ACTION, not public).
        const val QUICK_ACTION_EXTRA = "some unique action key"
    }
}
