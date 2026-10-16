# AiDM + Psiphon ecosystem — independent tools, shared proxy

**Architecture decision record:** 2026-10-16. **Status:** revised and agreed design; integration work remains planned.

> **Current decision supersedes the earlier two-Psiphon-engine proposal.** Only **Psiphon-Linux** will run the Psiphon engine. AiDM will not embed, package, launch, or maintain another copy. AiDM becomes optionally **SOCKS5 proxy-aware**.

## Motivation and decisive experiment

The original Windows inspiration was IDM downloading content through a Psiphon connection. On Linux, we now have separate working projects for the downloader (AiDM), browser media intelligence (AiDM Stream Inspector), and a native Psiphon tunnel (Psiphon-Linux).

The user successfully downloaded a URL from an ISP-blocked website using standalone Psiphon-Linux and:

```bash
yt-dlp --proxy "socks5h://127.0.0.1:1081" "URL"
```

The download both started and completed. This demonstrates the tested **yt-dlp → SOCKS5 → Psiphon** path. It does not establish that AiDM has implemented the feature or guarantee every URL, streaming protocol, or proxy provider works.

## Current conceptual architecture

```text
 Official Psiphon Tunnel Core (third-party upstream)
                       |
        Psiphon-Linux repository / verified build
                       |
            Standalone Psiphon app
         future GUI + tunnel management
                       |
             local SOCKS5 proxy
                (host + port)
                  /         \
                 /           \
       Firefox (via           AiDM
     Stream Inspector)    optional special
     optional browser      proxy mode
      proxy control      (yt-dlp only)
                 \           /
             media capture/handoff
```

All three tools remain independent in their primary function:
- **Psiphon-Linux:** standalone Psiphon engine, documented compiled binary, CLI functionality, and future full GUI (connection controls, countries, etc.). It supplies a local SOCKS5 proxy for apps that opt in.
- **AiDM:** full-featured downloader when proxy mode is OFF. When ON, it uses a saved external SOCKS5 address and routes a **single URL** to yt-dlp. It does not manage the Psiphon engine. Its setting can also target another SOCKS5 provider, such as Tor.
- **AiDM Stream Inspector:** browser media detection, ranking, titles, browser context and independent clipboard handoff. Optional, OFF-by-default, Firefox-only Psiphon control will eventually cooperate with standalone Psiphon-Linux. Chromium/Brave capture remains unaffected.

The Psiphon engine is **not copied into AiDM**; there is no second Psiphon instance or competing runtime datastore as part of this integration. The earlier rule to stop one engine before activating the other is therefore **obsolete for the adopted architecture**.

## AiDM's special proxy mode is deliberately limited

This is an occasional fallback for otherwise inaccessible content, **not** a second implementation of all AiDM download features.

**Settings UI:** SOCKS host, port, **Save** (persistent address), and a separate ON/OFF toggle; default OFF on new installations. No hardcoded Psiphon dependency. Normal AiDM does not require a proxy to be installed or running.

**When OFF:** AiDM's existing aria2c direct downloads, yt-dlp sites, streaming, bulk, playlists, subtitles, torrents and other features retain current behavior.

**When ON:** accept **one supported URL** and use yt-dlp with `--proxy socks5h://HOST:PORT`. In particular, a single direct HTTP/HTTPS link switches from aria2c to **yt-dlp**. A supported website URL or one HLS/DASH stream—including Stream Inspector handoff with available browser headers—also uses yt-dlp, as appropriate to its existing route. Do not build separate batch, playlist, subtitle or HLS/DASH architecture for proxy mode.

**Unavailable in special mode:** playlists, bulk sequential/parallel, separate subtitle-download workflow, torrent/magnet, aria2c acceleration and other incompatible advanced controls. Explicitly reject unsupported inputs; disable yt-dlp playlist traversal. On proxy failure, do **not** silently retry over the direct ISP connection. Request-context headers remain important; network reachability alone does not resolve expired signed URLs, authentication, DRM, or provider restrictions.

Exact acceptance tests and GUI behavior belong in [AiDM's special-mode plan](https://github.com/asif-AiML/AiDM/blob/feat/controls-settings/docs/proxy-aware-special-mode.md). The existing normal download settings design is not globally changed by the special mode's explicit Save action.

## Optional Firefox browser integration

The existing cross-browser Stream Inspector extension will gain a Firefox-only opt-in module **without losing Chromium functionality**.

Two distinct controls:
1. **Enable Psiphon Integration**, persistent, initially OFF: when disabled there is no Psiphon interaction, no proxy modification, no polling; stream inspection continues normally.
2. **Connect/Disconnect**, visible only when integration is enabled: coordinates the standalone Psiphon-Linux controller and Firefox proxy settings. Intended connection waits for actual tunnel readiness, not merely an open proxy port.

Intentional disconnect should restore the previously agreed/direct Firefox proxy policy; unexpected tunnel loss or controller failure must not silently bypass the proxy to expose direct ISP traffic. Supported permissions, communication transport, state restoration, and failure cases are **implementation research and testing tasks**, not established guarantees.

The extension may pass an observed stream with available browser context to AiDM; AiDM independently chooses its own routing mode. Firefox proxy configuration **does not automatically proxy external yt-dlp traffic**.

See the [extension's dedicated design](https://github.com/asif-AiML/AIDM-Stream-Inspector-Browser-Extension-/blob/feat/psiphon-firefox-integration/docs/psiphon-integration-vision.md).

## Development priorities

1. Preserve and improve Psiphon-Linux's known-good standalone engine; add process/lifecycle controller and eventually its own GUI.
2. Implement optional Firefox proxy switching on Stream Inspector's `feat/psiphon-firefox-integration` branch, preserving existing Firefox and Chromium workflows.
3. Independently implement AiDM's restricted proxy-aware special mode on `feat/controls-settings`, testing single direct and supported media/stream URLs with yt-dlp and no direct fallback.
4. Test the full browser-capture → AiDM handoff through a separately running SOCKS5 proxy, without merging repositories.

**Not in scope:** embedding Psiphon in AiDM, two competing Psiphon instances, tunnel sharing/handover, system-wide VPN routing for AiDM, or recreating all advanced AiDM features in proxy mode.

## Decision history

- **Earlier design (superseded):** two independent applications would package the same Psiphon engine; Stream Inspector could control both. This introduced duplicated binary packaging, two runtime instances, potential port collisions and manual shutdown of one app before using the other.
- **Current design (adopted after manual test):** a **single standalone Psiphon-Linux** process provides a standard local SOCKS5 proxy. AiDM is optionally proxy-aware through yt-dlp only; Stream Inspector optionally handles Firefox proxy/lifecycle controls. Independent products, no duplicated engine.

**Important evidence boundary:** standalone Psiphon SOCKS5 browsing and one yt-dlp proxied download are observed successes. AiDM GUI integration, Firefox auto-switching, long-session resilience and fresh-environment behavior must be tested separately.
