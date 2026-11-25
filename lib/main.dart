import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'features/leaderboard/leaderboard_store.dart';
import 'shared/env.dart';
import 'shared/env_error_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.offline && !Env.isConfigured) {
    runApp(
      EnvErrorScreen(
        missing: Env.missingFlags(Env.supabaseUrl, Env.supabaseAnonKey),
      ),
    );
    return;
  }
  // Pose scoring assumes a portrait camera image.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const WiggleMoveApp(),
    ),
  );
}
