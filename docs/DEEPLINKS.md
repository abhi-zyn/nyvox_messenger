# Invite links & QR codes

A Nyvox QR encodes an **https** invite URL:

```
https://vodttlhalrzqpsmowpaz.supabase.co/functions/v1/u/<accountId>
```

That URL is served by the `u` Supabase edge function (`supabase/functions/u/index.ts`).

## Why external scans used to fail

Google Lens opens the scanned URL in Chrome. Chrome on Android **blocks**
navigation to a custom scheme such as `nyvox://u/<id>`, so the old page
dead-ended. Android's supported hand-off is an `intent://` URL:

```
intent://u/<id>#Intent;scheme=nyvox;package=com.nyvox.nyvox_messenger;S.browser_fallback_url=<https fallback>;end
```

The function now emits that on Android (plain `nyvox://` on iOS) and keeps a
tappable "Open in Nyvox" button. If the app is not installed, Chrome opens
`S.browser_fallback_url` — today the same page with `?web=1`, which shows the
Account ID for manual entry. Point `FALLBACK_SITE` at your own website once
it exists.

## Required Android manifest entry

`android/` is generated, so the intent filter is applied by
`.github/workflows/build-apk.yml`. When building locally, add it yourself
inside the `<activity>` element of
`android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="nyvox" android:host="u" />
</intent-filter>
```

Verify it is registered on a running device:

```bash
adb shell am start -a android.intent.action.VIEW -d "nyvox://u/vc<64 hex chars>"
```

The app should open the chat. If you get `Error: Activity not started`, the
intent filter is missing from the installed APK — rebuild after editing the
manifest (`flutter run` does not re-generate it).

## Later: real App Links

Verified `https://` App Links need
`https://<your-domain>/.well-known/assetlinks.json` with the app's SHA-256
signing fingerprint. Supabase Functions cannot serve `/.well-known/`, so this
only becomes possible on your own domain. Until then, `intent://` is the
reliable path.
