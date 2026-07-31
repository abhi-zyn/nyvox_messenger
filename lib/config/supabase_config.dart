/// Supabase project credentials.
///
/// Get these from: Supabase Dashboard → Project Settings → API.
/// The anon key is safe to ship in the app — privacy is enforced by
/// Row Level Security policies (see supabase/schema.sql), and message
/// content is end-to-end encrypted so the server never sees plaintext.
///
/// Prefer passing them at build time:
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'YOUR_SUPABASE_URL',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_SUPABASE_ANON_KEY',
  );

  static bool get isConfigured =>
      !url.startsWith('YOUR_') && !anonKey.startsWith('YOUR_');
}
