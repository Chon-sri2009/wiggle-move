/// Build-time configuration, supplied with `--dart-define`.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Dev/test bypass: run the local-only app without Supabase keys.
  static const offline = bool.fromEnvironment('WM_OFFLINE');

  /// Live squat/lunge/jumping-jack form feedback from the trained model.
  /// Off by default: the model is not validated on a device yet.
  static const formCoach = bool.fromEnvironment('WM_FORM_COACH');

  static bool get isConfigured => hasKeys(supabaseUrl, supabaseAnonKey);

  /// True when both values are non-empty. Separate so it can be unit tested.
  static bool hasKeys(String url, String anonKey) =>
      url.isNotEmpty && anonKey.isNotEmpty;

  /// Offline mode skips real auth, so a release build must refuse it.
  static bool offlineForbidden({
    required bool offline,
    required bool release,
  }) => offline && release;

  /// The dart-define flag names that are missing for the given values.
  static List<String> missingFlags(String url, String anonKey) => [
    if (url.isEmpty) 'SUPABASE_URL',
    if (anonKey.isEmpty) 'SUPABASE_ANON_KEY',
  ];
}
