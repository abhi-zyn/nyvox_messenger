// Invite-link resolver for `https://<project>.supabase.co/functions/v1/u/<accountId>`.
//
// Scanning a Nyvox QR with Google Lens (or any external camera) opens this URL
// in Chrome. A plain `location.href = "nyvox://…"` redirect is blocked by
// Chrome on Android, which is why those scans used to dead-end on this page.
// Android's supported hand-off is an `intent://` URL, so that is what we use,
// with a browser fallback for people who do not have the app yet.

const PACKAGE = "com.nyvox.nyvox_messenger";
const ID_PATTERN = /^vc[0-9a-f]{64}$/;

/// Public base of this function. Behind Supabase's gateway `url.origin` is an
/// internal http:// address without the `/functions/v1` prefix, so the browser
/// fallback has to be built from a constant.
const INVITE_BASE =
  "https://vodttlhalrzqpsmowpaz.supabase.co/functions/v1/u";

/// Replace this with your own site once it exists; it is what Chrome opens
/// when Nyvox is not installed.
const FALLBACK_SITE = "";

function intentUrl(id: string, fallback: string): string {
  const parts = [
    "scheme=nyvox",
    `package=${PACKAGE}`,
    fallback ? `S.browser_fallback_url=${encodeURIComponent(fallback)}` : "",
    "end",
  ].filter(Boolean);
  return `intent://u/${id}#Intent;${parts.join(";")};`;
}

Deno.serve((req) => {
  const url = new URL(req.url);
  const id = url.pathname.split("/").filter(Boolean).pop() ?? "";
  const valid = ID_PATTERN.test(id);
  const ua = req.headers.get("user-agent") ?? "";
  const isAndroid = /android/i.test(ua);
  const isIos = /iphone|ipad|ipod/i.test(ua);

  // `?web=1` means we already bounced once: show the page, never redirect
  // again, so a missing app cannot cause a loop.
  const noRedirect = url.searchParams.has("web");
  const fallback = FALLBACK_SITE
    ? `${FALLBACK_SITE}/${id}`
    : `${INVITE_BASE}/${id}?web=1`;

  const deepLink = isAndroid ? intentUrl(id, fallback) : `nyvox://u/${id}`;
  const canRedirect = valid && !noRedirect && (isAndroid || isIos);

  const head = `<!doctype html><html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Nyvox — encrypted chat invite</title>
<style>
  :root { color-scheme: dark; }
  body { background:#0B0E11; color:#F2F5F7; margin:0; min-height:100vh;
         display:flex; align-items:center; justify-content:center;
         font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif; }
  .card { text-align:center; max-width:360px; padding:28px 24px; }
  h1 { color:#31F196; margin:8px 0 4px; font-size:28px; letter-spacing:.5px; }
  p { color:#8A939E; font-size:15px; line-height:1.5; }
  .cta { display:inline-block; background:#31F196; color:#04120B;
         padding:14px 30px; border-radius:14px; text-decoration:none;
         font-weight:700; margin-top:18px; }
  .id { display:block; margin-top:10px; padding:12px; border-radius:12px;
        background:#14181D; border:1px solid #262D36; color:#8A939E;
        font-family:ui-monospace,monospace; font-size:11px; word-break:break-all; }
  .hint { font-size:13px; margin-top:26px; }
  .err { color:#E5484D; }
</style></head><body><div class="card">
<h1>Nyvox</h1>`;

  const body = valid
    ? `<p>Someone invited you to an end-to-end encrypted chat.</p>
       <a class="cta" id="open" href="${deepLink}">Open in Nyvox</a>
       <p class="hint">Don't have Nyvox yet? Install it, then add this Account ID manually:</p>
       <span class="id">${id}</span>`
    : `<p class="err">This invite link is not valid.</p>`;

  // A short delay lets the page paint first; Chrome honours the intent:// hop.
  const auto = canRedirect
    ? `<script>setTimeout(function(){location.replace(${
      JSON.stringify(deepLink)
    })},250);</script>`
    : "";

  return new Response(`${head}${body}</div>${auto}</body></html>`, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    },
  });
});
