import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'shared/env.dart';
import 'shared/env_error_screen.dart';
import 'shared/legacy_data_migration.dart';
import 'shared/prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Offline mode has no real auth: never allow it in a shipped build.
  if (Env.offlineForbidden(offline: Env.offline, release: kReleaseMode)) {
    runApp(
      const EnvErrorScreen(
        title: 'Offline mode not allowed',
        message:
            'WM_OFFLINE=true is for development only and cannot be used in '
            'a release build. Build with SUPABASE_URL and SUPABASE_ANON_KEY.',
      ),
    );
    return;
  }
  if (!Env.offline && !Env.isConfigured) {
    runApp(
      EnvErrorScreen(
        missing: Env.missingFlags(Env.supabaseUrl, Env.supabaseAnonKey),
      ),
    );
    return;
  }
  if (!Env.offline) {
    // Restores a saved session from device storage before the first frame.
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }
  // Pose scoring assumes a portrait camera image.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  await migrateLegacyData(prefs, offline: Env.offline);
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const WiggleMoveApp(),
    ),
  );
}
