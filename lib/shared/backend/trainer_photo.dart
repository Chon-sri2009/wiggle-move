import '../env.dart';
import 'storage_url.dart';

/// Storage bucket of trainer photos (public read, service-role writes).
const trainerPhotoBucket = 'trainer-photos';

/// Public URL of a trainer photo, or null when there is no photo or no
/// backend configured (offline).
String? trainerPhotoUrl(String? path, {String base = Env.supabaseUrl}) =>
    publicStorageUrl(trainerPhotoBucket, path, base: base);
