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

There is a second constraint: the Supabase Functions gateway rewrites
`text/html` responses to `content-type: text/plain` and applies a
`sandbox` CSP, so an HTML landing page is displayed as raw source and its
JavaScript never runs. The function therefore returns **no HTML** — it answers
mobile browsers with a `302` straight to the intent URL (plain `nyvox://` on
iOS).

If the app is not installed, Chrome opens `S.browser_fallback_url` — today the
same endpoint with `?web=1`, which returns a short plain-text page containing
the Account ID. Point `FALLBACK_SITE` at your own website once it exists; a
site you control can also serve a proper branded HTML page.

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
