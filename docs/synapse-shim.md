# Design sketch: replacing Synapse behind a `THTTPSend` work-alike

**Status:** sketch / contingency. Not implemented. Written alongside the macOS
OpenSSL matched-pair fix (`ssl_openssl_lib.pas`).

## Why this might be wanted

transgui talks to the Transmission daemon over HTTP(S) using [Ararat
Synapse](http://www.ararat.cz/synapse/) (`synapse/source/lib/`). Synapse works,
but it is effectively unmaintained (last substantive releases ~2012) and its
OpenSSL loader has already needed macOS-specific surgery (versioned dylibs, the
matched-pair loader in `ssl_openssl_lib.pas`). If a future macOS/OpenSSL change
breaks Synapse again, or TLS 1.3 / modern cipher support becomes a problem,
swapping the transport is the escape hatch.

Other forks have taken the "update Synapse" route instead — e.g.
e-pas/transgui (`26c3005`, bump to a newer Synapse). That is the lighter option
if it suffices; this sketch is the heavier fallback for when a drop-in Synapse
update no longer cuts it.

**This is not currently needed.** Post-#1509 the transport works and the
matched-pair loader fixed the macOS startup issue. Do not undertake this unless
Synapse actually blocks something.

## The key insight: the app uses a *small* slice of Synapse

The whole point of this approach is to avoid touching call sites. transgui's
HTTP usage is concentrated and shallow, so a work-alike class exposing the same
surface lets `rpc.pas`, `about.pas` and `download.pas` compile unchanged.

The dependency surface, from the current code:

### `rpc.pas` (the RPC client — the bulk)
Uses a single `THTTPSend` instance (`TRpc.Http`) and these members:
- `THTTPSend.Create` / `.Free`
- `.Protocol` (`'1.1'`)
- `.Timeout`, and `.Sock.ConnectionTimeout` (connect timeout)
- `.Headers` (a `TStringList`-like: `.Clear`, `.Add`, `.Count`, indexed access,
  `.Values[...]`, `.NameValueSeparator`) — used for the
  `X-Transmission-Session-Id` handshake (HTTP 409) and `Location` (301)
- `.MimeType` (`'application/json'`)
- `.Document` (a `TMemoryStream`: `.Clear`, `.Write`, `.Position`, `.Memory`,
  `.Size`) — request and response body
- `.HTTPMethod('POST', URL)` -> Boolean
- `.ResultCode`, `.ResultString`
- `.Sock.LastErrorDesc`, `.Sock.CloseSocket`
- gzip: the response is gunzipped when `Content-Encoding: gzip` is present
  (see `CreateJsonParser`/`DecompressGzipContent`)

### `about.pas` and `download.pas` (simple GETs)
- `THTTPSend.Create`, `.HTTPMethod('GET', URL)`, `.Document`, `.ResultCode`.
  `download.pas` also references `synsock` for socket error symbols.

That is the entire contract. Everything else in Synapse is unused by transgui.

## The plan

1. **Define `TTransHttp`** (name TBD) in a new unit exposing exactly the members
   above with identical signatures/semantics — same `Document`/`Headers`
   objects, same `HTTPMethod` return convention, same `ResultCode`/`ResultString`,
   a `Sock` sub-object providing `LastErrorDesc`/`CloseSocket`/`ConnectionTimeout`.
2. **Back it with a modern transport.** Options, roughly in order of effort:
   - FPC's own `fphttpclient` (`TFPHTTPClient`) + `opensslsockets` — in-tree with
     FPC, supports HTTPS via OpenSSL, handles redirects and gzip-ish concerns.
     Lowest friction; the shim mostly adapts its API to the `THTTPSend` shape.
   - A platform-native client (NSURLSession on macOS, WinHTTP on Windows) behind
     the same shim — best TLS/keychain integration, most work, per-platform code.
3. **Preserve the quirks the daemon relies on:**
   - the `409` + `X-Transmission-Session-Id` retry handshake (currently in
     `rpc.pas`; keep it there, the shim just needs working header access),
   - `301` redirect handling (read `Location`),
   - gzip response decoding,
   - configurable overall + connect timeouts.
4. **Swap by `uses`**: replace `httpsend`/`ssl_openssl` in the three units with the
   shim unit; ideally keep the type name aliased so diffs stay tiny.
5. **Keep Synapse in-tree** initially, selectable via a compile define, so the
   change can be A/B tested against the daemon before Synapse is removed.

## Verification

Point both the Synapse build and the shim build at the same daemon and diff
behaviour: list torrents, add (file + magnet), start/stop/remove, set-location,
the 409 session-id handshake (first request after connect), a 301 redirect, and a
gzip response. The RPC JSON round-trips should be identical.

## Scope estimate

Small-to-moderate: the surface is ~15 members and 3 call sites. The real work is
faithfully reproducing the 409/301/gzip/timeout behaviour and validating TLS
against the daemon — not breadth.
