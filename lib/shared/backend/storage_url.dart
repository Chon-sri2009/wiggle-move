import '../env.dart';

/// Public URL of [path] in a public Storage [bucket], or null when there is no
/// path or no backend configured (offline). [base] is the Supabase project URL.
String? publicStorageUrl(
  String bucket,
  String? path, {
  String base = Env.supabaseUrl,
}) {
  if (path == null || path.isEmpty || base.isEmpty) return null;
  final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$root/storage/v1/object/public/$bucket/${Uri.encodeFull(path)}';
}
