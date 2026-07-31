# Building the APK with GitHub Actions

Every push to `main` (or a manual run) builds `app-release.apk` in the cloud —
no local Flutter install needed.

## One-time setup: add your Supabase secrets (2 minutes)

The workflow injects your Supabase credentials at build time via
`--dart-define`, so they are **never committed to git**.

1. Open the repo on GitHub → **Settings** → **Secrets and variables** → **Actions**.
2. Click **New repository secret** and add:

| Name                  | Value (Supabase Dashboard → Project Settings → API) |
| --------------------- | --------------------------------------------------- |
| `SUPABASE_URL`        | Project URL, e.g. `https://abcdefgh.supabase.co`    |
| `SUPABASE_ANON_KEY`   | `anon` / `public` key (the long JWT)                |

> Use the **anon public** key only — never the `service_role` key.

## Build & download the APK

1. Go to the repo → **Actions** tab → **Build Android APK**.
2. Click **Run workflow** → **Run workflow** (or just push a commit).
3. Wait ~5–8 minutes for the run to finish.
4. Open the completed run → scroll to **Artifacts** → download
   **`nyvox-release-apk`** (a zip containing `app-release.apk`).
5. Copy the APK to your phone and install it (allow "install unknown apps").

## Notes

- The workflow first runs `flutter create . --platforms=android` to generate
  the Android scaffold, since the repo intentionally contains only `lib/` and
  `pubspec.yaml`.
- `flutter analyze` runs in non-blocking mode — warnings won't fail the build.
- Builds without the secrets still succeed, but the app can't reach Supabase
  until you add them and rebuild.
- To ship via the Play Store later, build an App Bundle instead:
  `flutter build appbundle --release` (requires signing — see
  https://docs.flutter.dev/deployment/android#signing-the-app).
