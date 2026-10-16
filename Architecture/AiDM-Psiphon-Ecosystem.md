# AiDM + Psiphon: Independent Applications, Shared Engine

**Architecture decision record — 2026-10-16**  
**Status:** Agreed long-term direction. Most integrations described here are **planned**, not implemented.

## Origin and motivation

On Windows, Internet Download Manager (IDM) could download links from ISP-blocked sites when its traffic was configured to use Psiphon. The Linux goal is to recreate this useful **workflow**, not to copy the applications: a user encounters a blocked media URL, enables Psiphon when needed, and AiDM downloads through the available tunnel.

The foundation now exists in three separately developed projects:

- **[Psiphon-Linux](https://github.com/asif-AiML/Psiphon-Linux):** working Linux Psiphon ConsoleClient with a preserved, checksummed engine/configuration and verified Firefox SOCKS5 browsing. A standalone GUI, country selection and lifecycle integration are future work.
- **AiDM:** independently usable Linux download manager with different download engines (including yt-dlp and aria2c). An optional Psiphon toggle and proxy-aware downloading are future work.
- **[AiDM Stream Inspector](https://github.com/asif-AiML/AIDM-Stream-Inspector-Browser-Extension-):** independently usable Firefox/Chromium WebExtension for media detection and browser-context handoff. Optional Firefox Psiphon control is future work.

The current Psiphon setup has proven browser access to otherwise blocked websites and streaming playback. This **does not yet prove** AiDM can download through the Psiphon proxy.

## The architecture principle

> **One maintained Psiphon engine baseline, two independent applications adopting it, and one optional browser integration serving both — without turning any project into a hard dependency of another.**

The official [Psiphon Tunnel Core](https://github.com/Psiphon-Labs/psiphon-tunnel-core) remains the third-party upstream source. Our **Psiphon-Linux** repository maintains our validated Linux engine build, known-good public configuration, documentation, and future controller. It is an *internal baseline/integration foundation*, not a fork claiming to replace the official upstream.

```text
              Official Psiphon Tunnel Core
                          |
                validated Linux baseline
                          |
                      Psiphon-Linux
                          |
             +------------+-------------+
             |                          |
   Standalone Psiphon App          AiDM downloader
    own GUI + engine use          embedded engine use
   countries, connection         opt-in download proxy
       management                    toggle (OFF)
             |                          |
             +------ optional interface+
                          |
                 AiDM Stream Inspector
            browser media capture remains
            fully useful without Psiphon
```

The diagram shows **shared design/build provenance**, not a requirement for one application's process to be running before another can work. Each packaged application can include/use its own compatible engine executable while sharing upstream revision and tested integration patterns. Distribution must respect upstream and dependency licenses.

## Responsibilities and independence

| Component | Standalone function | Optional integration |
| --- | --- | --- |
| Psiphon-Linux application | Establish Psiphon tunnels and eventually offer a full Linux GUI, country choices, diagnostic and lifecycle controls | Expose a narrowly defined local controller/status interface to Stream Inspector |
| AiDM | Download from accessible sites with its normal direct, yt-dlp, aria2c and other workflows | Offer an OFF-by-default Psiphon control, explicitly route compatible downloader traffic through its embedded engine |
| AiDM Stream Inspector | Detect media, rank sources, capture available browser context, export selected items to AiDM | Optionally communicate with a Psiphon controller and configure **Firefox** proxy use |

**No mandatory coupling:** AiDM downloads without Psiphon; Psiphon-Linux works without AiDM; Stream Inspector detects/export media without either being installed or running. Psiphon must not become a required precondition of normal download or detection workflows.

## Initial single-instance rule (intentionally simple)

**Only one of the two Psiphon engine instances should be running at a time** in the initial product design:

1. To use AiDM's future embedded Psiphon, first **disconnect and stop** the standalone Psiphon application (not merely hide its window).
2. To use the standalone Psiphon app, first stop AiDM's embedded Psiphon engine.
3. The application starting a tunnel should make a **minimal proxy-port/process-conflict check** and refuse startup with a clear message if it cannot safely own its expected endpoints.
4. Each application must own its process and persistent runtime state independently; one must never kill or modify another's active process/datastore.

**Deferred deliberately:** multi-instance orchestration, dynamic port sharing/allocation, automatic handover, discovery of another app's active tunnel, and concurrent tunneling. They are *not* required for the initial integration.

This rule is a documented limitation plus basic collision avoidance—not proof that all possible process conflicts have been solved.

## Firefox-only extension integration

Stream Inspector remains one cross-browser extension. The Psiphon capability is **Firefox-first and optional**, disabled by default. On Chromium/Brave the feature should be hidden/inert and existing detection must remain unchanged.

Two independent concepts are required:

- **Enable Psiphon Integration** (persistent preference, default **OFF**): grants the extension's optional feature permission to operate. When OFF: no proxy switching, status polling, controller requests or unnecessary background activity; normal media capture continues.
- **Connect / Disconnect Psiphon** (available only when integration is enabled): requests lifecycle actions via a controller, and changes Firefox proxy routing when appropriate. Merely enabling integration must **not** connect a tunnel.

User-intent state is important:

| Event | Intended Firefox behavior |
| --- | --- |
| Integration disabled | Do not interfere with normal Stream Inspector behavior or proxy settings; if previously active, use a clearly authorized safe shutdown/restore procedure |
| User intentionally connects | Wait for **current-session tunnel readiness**, then configure Firefox SOCKS5 plus remote DNS |
| User intentionally disconnects | Stop the owned tunnel and restore the agreed previous/direct proxy policy |
| Tunnel crashes/disconnects unexpectedly | **Do not** silently route the browser directly through the ISP; retain the protected policy and show failure/recovery state |
| Chromium/Brave | No Firefox-only calls or Psiphon UI; preserve all existing capabilities |

This is a **target specification**, not currently delivered. Firefox permissions, actual proxy control, browser restart semantics, native messaging versus authenticated local communication, and saved prior proxy policies must be researched and tested. Avoid claims of system-wide VPN routing, a global kill switch, or complete anonymity.

The extension may eventually communicate with either application's compatible controller, but the **first integration target is standalone Psiphon-Linux**. A shared interface should be intentionally designed rather than introducing mandatory coupling or forcing an AiDM installation.

## AiDM embedded engine: future scope

The AiDM GUI should have a **small, simple Psiphon ON/OFF control**, OFF by default. Enabling it starts AiDM's **own** packaged engine instance after checking the single-instance rule. AiDM routes selected download requests through that engine, not automatically all traffic from Linux Mint.

This entails **engine-specific tests**: yt-dlp proxy options, aria2c supported proxy mechanisms, FFmpeg/fallback paths, DNS behavior, and browser-captured headers must be assessed separately. The Psiphon tunnel only solves applicable network reachability constraints; signed URL expiration, session authentication, missing Referer/User-Agent, unsupported formats and DRM can still cause failures.

Do not copy a separately evolving implementation of Psiphon into AiDM. Reuse a **pinned, independently validated engine build/interface** and track its provenance/checksums. Keep the original Psiphon-Linux project fully functional and maintainable as a standalone app.

## Development order and boundaries

1. **Preserve the working engine:** existing Psiphon-Linux baseline, checksums, recovery guide and independent CLI use. Already achieved for short Linux Mint sessions; long-session reliability is **not** proven.
2. **Firefox integration (current focus):** develop optional Psiphon control on Stream Inspector's `feat/psiphon-firefox-integration` branch. Start with API/permission/controller transport research; preserve Chromium behavior. Do not merge before Firefox and Brave regressions pass.
3. **Psiphon-Linux controller:** implement reliable lifecycle, state, readiness, intentional stop versus unexpected loss, and optional browser communication. Future standalone GUI may use the same engine/controller.
4. **AiDM integration (later):** package/use the validated Psiphon engine independently; opt-in GUI toggle, separate runtime/process, per-download proxy plumbing and tests.
5. **Broader UX after the foundations:** standalone Psiphon GUI including country choice, long-session recovery/testing and application packaging. Priority may change; do not bundle every aspiration into the initial Firefox milestone.
6. **Multiple instances (deferred):** revisit only if actual user needs justify the complexity.

Keep project-specific implementation decisions in the respective repositories. This document is the **cross-project architectural source of truth**, while the implementation repos record their own current tested behavior and version-specific details.

## Explicit non-goals for the first implementation

- No merging repositories.
- No new mandatory dependency between AiDM, Stream Inspector and standalone Psiphon-Linux.
- No two concurrent Psiphon instances to manage.
- No system-wide transparent tunneling required for the browser or download integration.
- No Chromium proxy-switching feature in the first extension release.
- No assumption that an active proxy port equals a live Psiphon tunnel.
- No claim that every blocked URL will download successfully.

## Related project documents

- [Psiphon-Linux known-good baseline](https://github.com/asif-AiML/Psiphon-Linux/blob/main/docs/known-good-baseline.md)
- [Psiphon-Linux reliability roadmap](https://github.com/asif-AiML/Psiphon-Linux/blob/main/docs/reliability-roadmap.md)
- [Stream Inspector integration vision](https://github.com/asif-AiML/AIDM-Stream-Inspector-Browser-Extension-/blob/feat/psiphon-firefox-integration/docs/psiphon-integration-vision.md)
- [Stream Inspector inspection and milestone plan](https://github.com/asif-AiML/AIDM-Stream-Inspector-Browser-Extension-/blob/feat/psiphon-firefox-integration/docs/psiphon-integration-inspection.md)

**Decision status:** agreed concept and product boundaries. Implementation details will evolve with evidence from real tests.
