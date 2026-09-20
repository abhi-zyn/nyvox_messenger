// Invite-link resolver for `https://<project>.supabase.co/functions/v1/u/<accountId>`.
//
// Two Android constraints shape this function:
//   1. Chrome blocks navigation to a custom scheme such as `nyvox://…`, so the
//      hand-off has to use an `intent://` URL.
//   2. The Supabase Functions gateway rewrites `text/html` responses to
//      `text/plain` and applies a `sandbox` CSP, so an HTML landing page is
//      shown as source and its JavaScript never runs.
//
// So we never return HTML: we answer with a 302 straight to the intent URL and
// let Chrome fall back to `S.browser_fallback_url` when the app is missing.
// Anything that is not a mobile browser gets a short plain-text page.

const PACKAGE = "com.nyvox.nyvox_messenger";
const ID_PATTERN = /^vc[0-9a-f]{64}$/;

/// Public base of this function. Behind the gateway `url.origin` is an
/// internal http:// address without the `/functions/v1` prefix, so the browser
/// fallback has to be built from a constant.
const INVITE_BASE =
  "https://vodttlhalrzqpsmowpaz.supabase.co/functions/v1/u";

/// Point this at your own site once it exists. It is what Chrome opens when
/// Nyvox is not installed.
const FALLBACK_SITE = "";

function intentUrl(id: string, fallback: string): string {
  return [
    `intent://u/${id}#Intent`,
    "scheme=nyvox",
    `package=${PACKAGE}`,
    `S.browser_fallback_url=${encodeURIComponent(fallback)}`,
    "end",
  ].join(";") + ";";
}

function textPage(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

Deno.serve((req) => {
  const url = new URL(req.url);
  const id = url.pathname.split("/").filter(Boolean).pop() ?? "";

  if (!ID_PATTERN.test(id)) {
    return textPage("Nyvox\n\nThis invite link is not valid.", 400);
  }

  const ua = req.headers.get("user-agent") ?? "";
  const isAndroid = /android/i.test(ua);
  const isIos = /iphone|ipad|ipod/i.test(ua);

  // `?web=1` is the fallback target: never redirect again from it, so a
  // missing app cannot cause a loop.
  const noRedirect = url.searchParams.has("web");
  const fallback = FALLBACK_SITE
    ? `${FALLBACK_SITE}/${id}`
    : `${INVITE_BASE}/${id}?web=1`;

  if (!noRedirect && (isAndroid || isIos)) {
    const target = isAndroid ? intentUrl(id, fallback) : `nyvox://u/${id}`;
    return new Response(null, {
      status: 302,
      headers: { location: target, "cache-control": "no-store" },
    });
  }

  return textPage(
    "Nyvox — send messages, not metadata\n\n" +
      "Someone invited you to an end-to-end encrypted chat.\n\n" +
      "Install Nyvox, then add this Account ID in the app\n" +
      "(New conversation → paste ID):\n\n" +
      `${id}\n`,
  );
});
