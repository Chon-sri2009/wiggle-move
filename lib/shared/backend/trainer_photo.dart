import '../env.dart';

/// Storage bucket of trainer photos (public read, service-role writes).
const trainerPhotoBucket = 'trainer-photos';

/// Public URL of a trainer photo, or null when there is no photo or no
/// backend configured (offline). [base] is the Supabase project URL.
String? trainerPhotoUrl(String? path, {String base = Env.supabaseUrl}) {
  if (path == null || path.isEmpty || base.isEmpty) return null;
  final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$root/storage/v1/object/public/$trainerPhotoBucket/'
      '${Uri.encodeFull(path)}';
}
