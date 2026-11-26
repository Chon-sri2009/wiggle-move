import '../env.dart';
import 'storage_url.dart';

/// Storage bucket of routine demonstration videos (WM-11: public read,
/// service-role writes).
const routineVideoBucket = 'routine-videos';

/// Public URL of a routine's video, or null when it has none or the app runs
/// offline.
String? routineVideoUrl(String? path, {String base = Env.supabaseUrl}) =>
    publicStorageUrl(routineVideoBucket, path, base: base);
