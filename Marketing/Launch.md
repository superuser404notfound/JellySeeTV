# JellySeeTV Public Beta Launch Kit

The public TestFlight is live. This file is the script for taking JellySeeTV public — GitHub announcement issue, Reddit posts, optional Mastodon/Bluesky/Show HN, and the cadence to follow so the discussion stays answered.

The vibe-coded disclosure is in every post on purpose. Self-hosted and Apple-platform audiences appreciate the upfront framing far more than they punish it. Trying to hide it would only invite suspicion later — the commit log has `Co-Authored-By: Claude` trailers anyway.

## Step 0: Pre-flight

* Public TestFlight link: `https://testflight.apple.com/join/eFKDaaXr`
* Public beta version: **0.3.2** — stable, plenty of internal testing, ready for outside eyes
* Apple TV Top Shelf integration and Siri voice commands are landed in `main` but **not yet in the public beta** (planned for 0.4.0). Keep them out of the launch copy below so installers don't go looking for features that aren't there yet.
* Privacy policy + imprint live at `https://jellyseetv.superuser404.de`
* `BETA.md` and the bug-report template are committed and visible
* 2x2 screenshot collage at `Screenshots/reddit-collage.jpg` for the Reddit posts

If anything in here references a different version number, replace it before posting.

## Step 1: Pin a GitHub announcement issue

GitHub → JellySeeTV repo → Issues → "New issue" → "Open a blank issue".

**Title:**
```
Public Beta is live. TestFlight link inside.
```

**Body:**
```markdown
JellySeeTV is now in public beta on TestFlight.

**Install:** https://testflight.apple.com/join/eFKDaaXr

You need an Apple TV 4K running tvOS 26 or later, plus your own Jellyfin server.

## What it does

* Native tvOS Jellyfin client with Direct Play for HEVC, HEVC Main10, AV1
* Real HDR10, Dolby Vision, HLG, with automatic display-mode switching
* Real Dolby Atmos via EAC3+JOC passthrough, wrapped as Dolby MAT 2.0 so your AVR's Atmos light actually comes on
* Built-in Jellyseerr browse and request flow as a first-class part of the UI
* 26 languages

## What it doesn't do

* No telemetry. No analytics. No tracking domains. No third-party SDKs
* No "rate this app" pop-up. No upsell screen. No social tab
* No login wall, no account, no marketing list — auth tokens stay in the system Keychain
* Privacy Manifest declares zero data collection because there is zero data collection

## Transparency: this is a vibe-coded project

I built JellySeeTV in close pair-programming with Claude (Anthropic). The architectural decisions are mine, every change went through a review loop before being committed, and the source is in this repo so you can audit it yourself rather than taking my word for it.

If you want to see how the code is structured before installing, browse the `JellySeeTV/` folder. The video engine lives separately at https://github.com/superuser404notfound/AetherEngine.

## What we want feedback on

See [BETA.md](BETA.md) for the full list and the bug-report template. The high-value areas:

* HDR display switching across different TV models and the Match Content setting
* Atmos passthrough on different AVRs (yours might do something mine doesn't)
* Seerr request flow when your library partially overlaps the catalog
* Server discovery on weird network setups (mDNS off, multiple subnets, VPN)

## How to report bugs

Open a new issue with the Bug Report template. Please include:

* App build (Settings → scroll to the bottom, e.g. `0.3.2 (1)`)
* tvOS version
* Steps to reproduce
* Photo of the screen if it's a visual bug

## What this beta is not

Not the App Store release. That comes after a few weeks of stable beta and a full review pass.

Crashes are possible. Apple TV won't be damaged but you may have to relaunch.

TestFlight builds expire after 90 days. New builds replace the old one automatically when you have TestFlight installed.

## Links

Code: this repo
Engine: https://github.com/superuser404notfound/AetherEngine
Privacy policy: https://jellyseetv.superuser404.de/privacy
Imprint: https://jellyseetv.superuser404.de/imprint

Thanks for testing.
```

After posting: ⋯ menu → "Pin issue".

## Step 2: Reddit posts

Three subreddits, three slightly different framings. **Don't post all three within a few hours of each other** — Reddit's spam filters dislike that pattern, and you also need bandwidth to answer comments under each one. Spread them over two or three days.

Each post should embed `Screenshots/reddit-collage.jpg` once, near the top, right after the intro paragraph.

### r/jellyfin

**Title:**
```
[Beta] JellySeeTV: a fast, native tvOS Jellyfin client with built-in Jellyseerr (open source, GPL-3.0)
```

**Body:**
```markdown
Hey r/jellyfin,

I built JellySeeTV, a native Apple TV client for Jellyfin with first-class Jellyseerr integration. After a few months of work and a chunk of internal testing, it's stable enough for a public TestFlight beta.

[2x2 screenshot collage embedded here]

**TestFlight:** https://testflight.apple.com/join/eFKDaaXr
**Source:** https://github.com/superuser404notfound/JellySeeTV

## What it is

A focused, fast Apple TV client. SwiftUI on top of a custom video engine that talks directly to FFmpeg, VideoToolbox, and AVPlayer — same focus engine, transport bar, and info-panel patterns the Apple TV+ app uses. Cold-launches quickly, scrolls smoothly, gets out of your way.

The Jellyseerr piece is what I personally was missing. I want to browse trending content and request things from the couch without switching to a phone or a web UI. So that's a first-class part of the app, not a separate tab linking out.

## Highlights

* Direct Play for almost every codec your Apple TV understands: H.264, HEVC, HEVC Main10, AV1
* Real HDR10 and Dolby Vision with automatic display-mode switching (Match Content)
* Real Dolby Atmos via EAC3+JOC, wrapped as Dolby MAT 2.0, so your AVR's Atmos light actually lights up
* Resume across devices, intro skip, next-episode autoplay
* Subtitle and audio-track switching mid-playback
* 26 languages

## What you won't find in it

* No telemetry, no analytics, no tracking domains, no third-party SDKs
* No upsell tab, no "rate this app" pop-up, no marketing newsletter prompt
* No login wall — you connect to your server, that's it
* Lean dependency graph: AVFoundation, VideoToolbox, FFmpeg, and the Jellyfin/Jellyseerr APIs themselves. That's it
* GPL-3.0 with App Store Exception, fully auditable

## A note on how this was built

JellySeeTV is vibe-coded. I built it in close pair-programming with Claude (Anthropic). The architecture, the design decisions, and the review of every commit are mine. The code is open and in the repo precisely so it's not a "trust me bro" situation — if you want to see how a particular feature is structured before installing, look at it directly.

The video engine is split out into its own LGPL-3.0 package ([AetherEngine](https://github.com/superuser404notfound/AetherEngine)) so it's reusable and reviewable on its own. Both the engine and the app shell ship under copyleft (LGPL / GPL respectively) with an Apple Store / DRM Exception that keeps the App Store and TestFlight distribution paths legally clean.

## Requirements

* Apple TV 4K (any generation)
* tvOS 26.0 or later
* Your own Jellyfin server (10.9+ recommended)
* Optional: Jellyseerr (2.0+) for the request flow

## What I'd love feedback on

* HDR and Dolby Vision behavior on different TVs
* Atmos passthrough on various AVRs
* Edge cases in server discovery
* Anything that crashes

Bug reports: GitHub issues are open with templates at https://github.com/superuser404notfound/JellySeeTV/issues

Happy to answer technical questions in the thread.
```

### r/selfhosted

**Title:**
```
[Beta] JellySeeTV: open-source native Apple TV client for Jellyfin and Jellyseerr (GPL-3.0, no telemetry, vibe-coded but auditable)
```

**Body:**
```markdown
Hey r/selfhosted,

If you self-host Jellyfin and have an Apple TV in the living room, JellySeeTV might be your missing piece. Native tvOS app, GPL-3.0 with App Store Exception, no telemetry, with built-in Jellyseerr integration so you can browse and request from the same UI.

[2x2 screenshot collage embedded here]

**TestFlight:** https://testflight.apple.com/join/eFKDaaXr
**Source and audit:** https://github.com/superuser404notfound/JellySeeTV
**Privacy policy:** https://jellyseetv.superuser404.de/privacy (zero data collected)

## What it is

* Native Apple TV client for Jellyfin
* Jellyseerr request flow built in: browse trending, request, track status, all on the TV
* Direct Play for HEVC, HEVC Main10, AV1, with HDR10, Dolby Vision, Dolby Atmos
* Custom FFmpeg + VideoToolbox video engine
* Open source, GPL-3.0 with App Store Exception. Fork it, audit it, ship your own version if you keep it open

## Lean by design

* No telemetry. No analytics. No tracking domains. No crash-reporting SDK that quietly phones home
* No third-party SDKs of any kind
* Dependency graph fits on a napkin: AVFoundation, VideoToolbox, FFmpeg (LGPL build, dynamic-linkable for App Store compliance), and the Jellyfin/Jellyseerr APIs themselves
* Credentials live in the system Keychain, never written to disk in plaintext, never logged
* Network traffic is auditable: open `JellySeeTV/Services/` and you'll see exactly what's sent and where
* The Privacy Manifest declares zero data collection because there is zero data collection

## On vibe-coding, since this community will rightly ask

I built this in close pair-programming with Claude. I want to be upfront about that because the term "vibe-coded" tends to come with the assumption of slop. This is the opposite of slop:

* Every commit was reviewed before landing. Look at the git log: descriptive messages, focused diffs, no auto-generated noise
* If you spot something wrong, file an issue or open a PR. The point of being open source is that you don't have to trust me, you can verify

## Why open source

For the same reason you self-host Jellyfin in the first place. The video engine ([AetherEngine](https://github.com/superuser404notfound/AetherEngine)) is LGPL-3.0 separately so it's reusable. The app shell on top is GPL-3.0. Both carry an App Store / DRM Exception so the App Store and TestFlight distribution paths stay legally clean.

## Tech stack for the curious

* SwiftUI with UIKit interop where it matters (player VC, gesture recognizers)
* AVSampleBufferDisplayLayer driven by a CMTimebase synced to the audio clock
* Local HLS server in-process to wrap EAC3+JOC into Dolby MAT 2.0 for Atmos passthrough through AVPlayer
* Demux via FFmpeg, decode via VideoToolbox where possible, software fallback (dav1d) for AV1 on older hardware
* Keychain for credentials, UserDefaults for preferences, nothing leaves the device

## Beta status

Internal testing has been running for a while; smoke tests pass; HDR and Atmos work on my own setup but I want feedback from more TVs and more receivers.

Requirements: Apple TV 4K, tvOS 26+, your own Jellyfin server.

Bug reports welcome on GitHub.
```

### r/AppleTV

**Title:**
```
JellySeeTV: open-source native Jellyfin client for Apple TV is in public beta — fast, lean, real HDR + Atmos
```

**Body:**
```markdown
For the Jellyfin users in here: JellySeeTV is now in public TestFlight beta.

[2x2 screenshot collage embedded here]

**Install:** https://testflight.apple.com/join/eFKDaaXr

Native tvOS app. Proper transport bar, focus engine, HDR and Dolby Vision display switching, Dolby Atmos via EAC3+JOC passthrough. Built ground-up on SwiftUI plus a custom video engine. Cold-launches quickly, scrolls smoothly, stays out of the way.

Plus first-class Jellyseerr integration if you use that, so you can browse trending and request stuff directly from the couch.

**Lean:** No telemetry, no analytics, no third-party SDKs, no upsell pop-ups. The Privacy Manifest declares zero data collection because there is zero data collection.

**Requirements:** Apple TV 4K, tvOS 26+, your own Jellyfin server.

It's GPL-3.0 licensed (with an Apple Store Exception so the App Store distribution stays legal) and fully open source. Code is at https://github.com/superuser404notfound/JellySeeTV. The app was built in pair-programming with Claude (Anthropic), with every change reviewed before commit, and the source is open so you can verify what it does before installing.

Feedback welcome, particularly on HDR / Dolby Vision behavior across different TV models and Atmos handling on various AVRs. Bug reports go in GitHub Issues.
```

## Step 3 (optional): Mastodon and Bluesky

Short version, fits in a single post on either platform:

```
JellySeeTV: open-source native Jellyfin client for Apple TV with built-in Jellyseerr is now in public TestFlight beta.

Fast. Lean. Real HDR10. Real Dolby Vision. Real Dolby Atmos. No telemetry, no analytics, no third-party SDKs. GPL-3.0 with App Store Exception. Vibe-coded with Claude, every change reviewed, source is open.

TestFlight: https://testflight.apple.com/join/eFKDaaXr
Source: https://github.com/superuser404notfound/JellySeeTV

Apple TV 4K and tvOS 26+ required.
```

## Step 4 (optional): Show HN

Show HN is worth a try if you want broader tech reach. The HN audience is generally skeptical of AI-assisted code but rewards directness and honesty. Don't try to hide the vibe-coding angle, lead with it.

**Title:**
```
Show HN: JellySeeTV, open-source native Apple TV client for Jellyfin and Jellyseerr
```

**URL field:** `https://github.com/superuser404notfound/JellySeeTV`
**Text field:** leave blank. The HN convention for Show HN with a URL is empty body, the discussion lives in the comments.

If it gets traction, plan to hang in the comments for a few hours. Be honest about the vibe-coding workflow, point at concrete architectural decisions in the code (the Atmos MAT-wrapping, the AVPlayerItem.timebase video sync, the lean dependency graph), and answer technical questions promptly. That's what wins HN over.

## Step 5: After launch, what to watch

* **GitHub Issues:** primary feedback channel
* **TestFlight Feedback:** in-app screenshots and system info, viewable in App Store Connect → TestFlight → Feedback
* **Reddit comments:** answer technical questions, take feature requests as informal signal
* **Crash reports:** App Store Connect → TestFlight → Crashes (if any come in)

## Cadence

Spread the announcements over a few days so you can answer comments without burning out.

* **Today:** post the pinned GitHub issue, then post on **r/jellyfin**
* **+1 day:** post on **r/selfhosted**
* **+2 days:** post on **r/AppleTV**
* **+3 to 7 days:** triage feedback, fix critical bugs, push new builds (the in-flight 0.4.0 with Top Shelf + Siri lands in this window)
* **+7 days onward:** Mastodon and Bluesky, then Show HN if you're feeling brave
* **0.4.0 ships to TestFlight:** worth a brief follow-up comment on the original Reddit threads — "build 0.4.0 just landed with Top Shelf + Siri voice control, give it another spin"
* **After two or three weeks of stable use:** consider App Store submission

Don't try to be everywhere on day 0. Reddit appreciates posts that get answered, not posted-and-forgotten.

## A note on tone

The disclosure of vibe-coding is included in every post on purpose. Hiding it would invite suspicion if anyone discovered it later (and they would — the commit messages have `Co-Authored-By: Claude` trailers). Leading with it shows confidence in the actual work.

The framing matters: "vibe-coded but auditable" is an honest claim that the code is reviewed and reviewable. "Vibe-coded slop" is what people fear. The way to defuse the fear is to invite people to look at the code themselves.

Two things to avoid in the comment threads:

1. **Don't bash other clients by name.** No "VLCKit is bad" or "Swiftfin doesn't do X". You're standing on what JellySeeTV is, not on what others aren't. If someone else brings up a comparison in a comment, answer factually about your own design choices and stop there.
2. **Don't oversell.** "Fast" and "lean" are claims people will test. They mostly hold up — but if a feature isn't there yet (Top Shelf, Siri, downloads), say so directly. Honesty compounds; spin gets caught.
