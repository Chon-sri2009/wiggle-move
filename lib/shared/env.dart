/// Build-time configuration, supplied with `--dart-define`.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Dev/test bypass: run the local-only app without Supabase keys.
  static const offline = bool.fromEnvironment('WM_OFFLINE');

  static bool get isConfigured => hasKeys(supabaseUrl, supabaseAnonKey);

  /// True when both values are non-empty. Separate so it can be unit tested.
  static bool hasKeys(String url, String anonKey) =>
      url.isNotEmpty && anonKey.isNotEmpty;

  /// The dart-define flag names that are missing for the given values.
  static List<String> missingFlags(String url, String anonKey) => [
    if (url.isEmpty) 'SUPABASE_URL',
    if (anonKey.isEmpty) 'SUPABASE_ANON_KEY',
  ];
}
