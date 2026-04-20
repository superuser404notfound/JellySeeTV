# JellySeeTV Public Beta Launch Kit

Everything you need to announce the open beta once Apple's Beta App Review approves the External Testing group and gives you a public TestFlight link.

## Step 0: Get the public TestFlight link

1. App Store Connect, JellySeeTV, TestFlight, Externe Gruppen, Public Beta
2. After Apple approves: toggle "Public Link aktivieren"
3. Copy the URL (`https://testflight.apple.com/join/XXXXXXXX`)
4. Find and replace `REPLACE_ME` in:
   * `README.md`
   * This file (in the post drafts below)
5. Commit, push, then proceed with the announcements.

## Step 1: Pin a GitHub announcement issue

GitHub, JellySeeTV repo, Issues, "New issue", "Open a blank issue" (skip the templates).

**Title:**
```
Public Beta is live. TestFlight link inside.
```

**Body:**
```markdown
JellySeeTV is now in public beta on TestFlight.

**Install:** https://testflight.apple.com/join/REPLACE_ME

You need an Apple TV 4K running tvOS 26 or later, plus your own Jellyfin server.

## What this beta does

* Native tvOS Jellyfin client with Direct Play for HEVC, HEVC Main10, AV1
* Real HDR10, Dolby Vision, HLG, with automatic display mode switching
* Real Dolby Atmos via EAC3+JOC passthrough, wrapped as Dolby MAT 2.0 so your AVR's Atmos light actually comes on
* Built-in Jellyseerr browse and request flow as a first class part of the UI, not a tacked-on link
* 26 languages
* MIT licensed, fully open source, no telemetry

## Transparency: this is a vibe-coded project

I built JellySeeTV in close pair-programming with Claude (Anthropic). The design decisions are mine, every change went through a review loop before being committed, and the source is in this repo so you can audit it yourself rather than taking my word for it.

The Privacy Manifest declares zero data collection. No analytics, no third-party SDKs. Auth tokens stay in the system Keychain. The only network traffic is to the servers you point the app at.

If you want to see how the code is structured before installing, browse the `JellySeeTV/` folder. If you want to see the video engine, that's a separate package at https://github.com/superuser404notfound/AetherEngine.

## What we want feedback on

See [BETA.md](BETA.md) for the full list and the bug report template. The high value areas:

* HDR display switching across different TV models and the Match Content setting
* Atmos passthrough on different AVRs
* Seerr request flow when your library is partially overlapping the catalog
* Server discovery on weird network setups (mDNS off, multiple subnets, VPN)

## How to report bugs

Open a new issue using the Bug Report template. Please include:

* App build (Settings, scroll to the bottom, e.g. `0.1.0 (1)`)
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

After posting: ⋯ menu, "Pin issue".

## Step 2: Reddit posts

Three subreddits, three slightly different framings. Don't post all three within a few hours of each other. Reddit's spam filters dislike that pattern, and you also need bandwidth to answer comments under each one. Spread them over two or three days.

The vibe-coded disclosure is in every post on purpose. Self-hosted and developer audiences appreciate the upfront framing more than they punish it. Trying to hide it would only invite suspicion later.

### r/jellyfin

**Title:**
```
[Beta] JellySeeTV: native tvOS client with built-in Jellyseerr (open source, MIT)
```

**Body:**
```markdown
Hey r/jellyfin,

I built JellySeeTV, a native Apple TV client for Jellyfin with first class Jellyseerr integration. After several months of work it's at the point where it's stable enough for a public TestFlight beta.

**TestFlight:** https://testflight.apple.com/join/REPLACE_ME
**Source:** https://github.com/superuser404notfound/JellySeeTV

## Why another client

The existing Apple TV options are either Swiftfin, which is great but uses VLCKit and doesn't always handle HDR cleanly, or web-wrapped clients that fight tvOS instead of using it. JellySeeTV is built ground up native: SwiftUI, with a custom video engine on top of FFmpeg, VideoToolbox, and AVPlayer. Same focus engine, transport bar, and info panel patterns that Apple TV+ uses.

The Jellyseerr piece is what I personally was missing. I want to browse trending content and request things from the couch without switching to a phone or a web UI. So that's a first class part of the app.

## Highlights

* Direct Play for almost every codec your Apple TV understands: H.264, HEVC, HEVC Main10, AV1
* Real HDR10 and Dolby Vision with automatic display mode switching (Match Content)
* Real Dolby Atmos via EAC3+JOC, wrapped as Dolby MAT 2.0, so your AVR's Atmos light actually lights up
* Resume across devices, intro skip, next-episode autoplay
* Subtitle and audio track switching mid playback
* 26 languages
* No telemetry, no analytics, no third-party SDKs. MIT licensed, fully auditable

## A note on how this was built

JellySeeTV is vibe-coded. I built it in close pair-programming with Claude (Anthropic). The architecture, the design decisions, and the review of every commit are mine. The code is open and in the repo precisely so it's not a "trust me bro" situation. If you want to see how a particular feature is structured before installing, look at it directly.

The video engine is split out into its own LGPL-3.0 package ([AetherEngine](https://github.com/superuser404notfound/AetherEngine)) so it's reusable and reviewable on its own. The app shell on top is MIT.

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
[Beta] JellySeeTV: open source native Apple TV client for Jellyfin and Jellyseerr (MIT, no telemetry, vibe-coded but auditable)
```

**Body:**
```markdown
Hey r/selfhosted,

If you self host Jellyfin and have an Apple TV in the living room, JellySeeTV might be your missing piece. Native tvOS app, MIT licensed, no telemetry, with built-in Jellyseerr integration so you can browse and request from the same UI.

**TestFlight:** https://testflight.apple.com/join/REPLACE_ME
**Source and audit:** https://github.com/superuser404notfound/JellySeeTV
**Privacy policy:** https://jellyseetv.superuser404.de/privacy (zero data collected)

## What it is

* Native Apple TV client for Jellyfin
* Jellyseerr request flow built in: browse trending, request, track status, all on the TV
* Direct Play for HEVC, HEVC Main10, AV1, with HDR10, Dolby Vision, Dolby Atmos
* Custom FFmpeg + VideoToolbox engine, no VLCKit
* Open source, MIT, fork it, audit it, ship your own version if you want

## On vibe-coding, since this community will rightly ask

I built this in close pair-programming with Claude. I want to be upfront about that because the term "vibe-coded" tends to come with the assumption of slop. This is the opposite of slop:

* Every commit was reviewed before landing. Look at the git log: descriptive messages, focused diffs, no auto-generated noise
* The Privacy Manifest is honest: no data collection, no tracking domains, no third-party SDKs
* Network traffic is auditable: open `JellySeeTV/Services/` and you'll see exactly what's sent and where
* Credentials live in the iOS Keychain, never written to disk in plaintext, never logged
* The dependency graph is small and named: AVFoundation, VideoToolbox, FFmpeg (LGPL build, dynamic linkable for App Store compliance), and that's basically it

If you spot something wrong, file an issue or open a PR. The point of being open source is that you don't have to trust me, you can verify.

## Why open source

For the same reason you self host Jellyfin in the first place. The other Apple TV options are closed source binaries you have to trust. This one isn't.

The video engine ([AetherEngine](https://github.com/superuser404notfound/AetherEngine)) is LGPL-3.0 separately so it's reusable. The app shell on top is MIT.

## Tech stack for the curious

* SwiftUI with UIKit interop where it matters (player VC, gesture recognizers)
* AVSampleBufferDisplayLayer driven by a CMTimebase synced to the audio clock
* Local HLS server in process to wrap EAC3+JOC into Dolby MAT 2.0 for Atmos passthrough through AVPlayer
* Demux via FFmpeg, decode via VideoToolbox where possible, software fallback (dav1d) for AV1 on older hardware
* Keychain for credentials, UserDefaults for preferences, nothing leaves the device

## Beta status

This is the first public TestFlight. Internal testing has been running for a while; smoke tests pass; HDR and Atmos work on my own setup but I want feedback from more TVs and more receivers.

Requirements: Apple TV 4K, tvOS 26+, your own Jellyfin server.

Bug reports welcome on GitHub.
```

### r/AppleTV

**Title:**
```
JellySeeTV: open source native Jellyfin client for Apple TV is in public beta
```

**Body:**
```markdown
For the Jellyfin users in here: JellySeeTV is now in public TestFlight beta.

**Install:** https://testflight.apple.com/join/REPLACE_ME

Native tvOS app. Proper transport bar, focus engine, HDR and Dolby Vision display switching, Dolby Atmos via EAC3+JOC passthrough. Built from scratch on SwiftUI plus a custom video engine. No VLCKit, no web view.

Plus first class Jellyseerr integration if you use that, so you can browse trending and request stuff directly from the couch.

**Requirements:** Apple TV 4K, tvOS 26+, your own Jellyfin server.

It's MIT licensed and fully open source. Code is at https://github.com/superuser404notfound/JellySeeTV. No telemetry, no analytics. The app was built in pair-programming with Claude (Anthropic), with every change reviewed before commit, and the source is open so you can verify what it does before installing.

Feedback welcome, particularly on HDR and Dolby Vision behavior across different TV models and Atmos handling on various AVRs. Bug reports go in GitHub Issues.
```

## Step 3 (optional): Mastodon and Bluesky

Short version, fits in a single post on either platform:

```
JellySeeTV: open source native Jellyfin client for Apple TV with built-in Jellyseerr is now in public TestFlight beta.

Direct Play, real HDR10, real Dolby Vision, real Dolby Atmos. MIT licensed, no telemetry. Vibe-coded with Claude, every change reviewed, source is open.

TestFlight: https://testflight.apple.com/join/REPLACE_ME
Source: https://github.com/superuser404notfound/JellySeeTV

Apple TV 4K and tvOS 26+ required.
```

## Step 4 (optional): Show HN

Show HN is worth a try if you want broader tech reach. The HN audience is generally skeptical of AI-assisted code but rewards directness and honesty. Don't try to hide the vibe-coding angle, lead with it.

**Title:**
```
Show HN: JellySeeTV, open source native Apple TV client for Jellyfin and Jellyseerr
```

**URL field:** `https://github.com/superuser404notfound/JellySeeTV`
**Text field:** leave blank. The HN convention for Show HN with a URL is empty body, the discussion lives in the comments.

If it gets traction, plan to hang in the comments for a few hours. Be honest about the vibe-coding workflow, show the architectural thinking behind specific decisions, and answer technical questions promptly. That's what wins HN over.

## Step 5: After launch, what to watch

* **GitHub Issues:** primary feedback channel
* **TestFlight Feedback:** in-app screenshots and system info, viewable in App Store Connect, TestFlight, Feedback
* **Reddit comments:** answer technical questions, take feature requests as informal signal
* **Crash reports:** App Store Connect, TestFlight, Crashes (if any come in)

## Cadence

* **Day 0:** TestFlight approved, update README link, post the pinned GitHub issue, post on r/jellyfin
* **Day 1 or 2:** post on r/selfhosted (and r/AppleTV optionally)
* **Day 3 to 7:** triage feedback, fix critical bugs, push new builds
* **Day 7+:** Mastodon and Bluesky if you want, Show HN if you're feeling brave
* **After two or three weeks of stable use:** consider App Store Submission

Don't try to be everywhere on day 0. Reddit appreciates posts that get answered, not posted-and-forgotten. Pace it.

## A note on tone

The disclosure of vibe-coding is included in every post on purpose. Hiding it would invite suspicion if anyone discovered it later (and they would, the commit messages have `Co-Authored-By: Claude` trailers). Leading with it shows confidence in the actual work.

The framing matters: "vibe-coded but auditable" is an honest claim that the code is reviewed and reviewable. "Vibe-coded slop" is what people fear. The way to defuse the fear is to invite people to look at the code themselves.
