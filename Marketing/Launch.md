# JellySeeTV — Public Beta Launch Kit

Everything you need to announce the open beta once Apple's Beta App Review approves the External Testing group and gives you a public TestFlight link.

## Step 0 — Get the public TestFlight link

1. App Store Connect → JellySeeTV → TestFlight → Externe Gruppen → Public Beta
2. After Apple approves: **„Public Link aktivieren"** toggle
3. Copy the URL (`https://testflight.apple.com/join/XXXXXXXX`)
4. Find-and-replace `REPLACE_ME` in:
   - `README.md`
   - This file (below in the post drafts)
   - `BETA.md` (only if you want — it currently says „install TestFlight + accept invite", which is the email path)

## Step 1 — Pin a GitHub announcement issue

GitHub → JellySeeTV repo → Issues → **New issue** → **Open a blank issue** (skip templates).

**Title:**
```
🧪 Public Beta is live — TestFlight link inside
```

**Body:**
```markdown
JellySeeTV is now in public beta on TestFlight.

**Install:** https://testflight.apple.com/join/REPLACE_ME

(You need an Apple TV 4K running tvOS 26+ and your own Jellyfin server.)

## What's in this beta

- Native tvOS Jellyfin client — Direct Play for HEVC, HDR10, Dolby Vision, HLG
- Real Dolby Atmos via EAC3+JOC passthrough (your AVR's Atmos light comes on)
- First-class Seerr/Jellyseerr integration — browse trending and request from the same app
- 26 languages
- MIT-licensed, no telemetry, fully open source

## What we want feedback on

See [BETA.md](BETA.md) for the test focus and bug-report template.

The high-value areas:
- HDR display switching (Match Content)
- Atmos passthrough on different AVRs
- Seerr request flow
- Server discovery on weird network setups

## How to report bugs

Open a new issue using the **Bug Report** template. Please include:
- App build (Settings → bottom of the screen, e.g. `1.0.0 (3)`)
- tvOS version
- Steps to reproduce
- Photo of the screen if it's a visual bug

## What this beta is NOT

- Not the App Store release (that comes after a few weeks of stable beta)
- Crashes are possible — Apple TV won't be damaged but you may have to relaunch
- TestFlight builds expire after 90 days; new builds replace them automatically

## Open source

Code: this repo
Engine: https://github.com/superuser404notfound/AetherEngine
Privacy policy: https://jellyseetv.superuser404.de/privacy

Thanks for testing.
```

After posting: **⋯ menu → Pin issue** so it sticks at the top of the issue list.

## Step 2 — Reddit announcement posts

Three posts, three subreddits, three slightly different framings. Don't post all three within a few hours of each other — Reddit's spam filters dislike that. Spread over 2-3 days.

---

### r/jellyfin

**Title:**
```
[Beta] JellySeeTV — native tvOS client with built-in Jellyseerr (open source, MIT)
```

**Body:**
```markdown
Hey r/jellyfin,

I built JellySeeTV — a native Apple TV client for Jellyfin with first-class Jellyseerr integration baked in. After a few months of vibe-coding it together I'm at the point where it's stable enough for a public TestFlight beta.

**TestFlight:** https://testflight.apple.com/join/REPLACE_ME
**Source:** https://github.com/superuser404notfound/JellySeeTV

## Why another client

The existing Apple TV options are either Swiftfin (great but VLCKit-based, doesn't always handle HDR cleanly) or web-wrapped clients that fight tvOS. JellySeeTV is built ground-up native: SwiftUI, custom video engine on top of FFmpeg + VideoToolbox + AVPlayer, same focus engine and transport bar as Apple TV+.

The Jellyseerr piece is what I personally was missing — I want to be able to browse trending content and request things directly from the couch instead of switching to a phone or web UI. So that's a first-class part of the app, not an afterthought link.

## Highlights

- **Direct Play** for almost everything: H.264, HEVC, HEVC Main10, AV1
- **Real HDR10 / Dolby Vision** with display mode switching
- **Real Dolby Atmos** via EAC3+JOC → Dolby MAT 2.0 (your AVR's Atmos light actually lights up)
- Resume across devices, intro skip, next-episode autoplay
- Subtitle + audio track switching mid-playback
- 26 languages
- **No telemetry, no analytics, no third-party SDKs.** MIT-licensed, fully auditable.

## Requirements

- Apple TV 4K (any gen)
- tvOS 26.0+
- Your own Jellyfin server (10.9+ recommended)
- Optional: Jellyseerr (2.0+) for the request flow

## Things I'd love feedback on

- HDR / Dolby Vision behavior on different TVs
- Atmos passthrough on various AVRs
- Edge cases in Server Discovery
- Anything that crashes 🙃

Bug reports: GitHub issues are open with templates → https://github.com/superuser404notfound/JellySeeTV/issues

Happy to answer any questions in the thread.
```

---

### r/selfhosted

**Title:**
```
[Beta] JellySeeTV — open-source native Apple TV client for Jellyfin + Jellyseerr (no telemetry, MIT)
```

**Body:**
```markdown
Hey r/selfhosted,

If you self-host Jellyfin and have an Apple TV in the living room, JellySeeTV might be your missing piece. Native tvOS app, MIT-licensed, no telemetry, with built-in Jellyseerr integration so you can browse and request from the same UI.

**TestFlight:** https://testflight.apple.com/join/REPLACE_ME
**Source + audit:** https://github.com/superuser404notfound/JellySeeTV
**Privacy policy:** https://jellyseetv.superuser404.de/privacy (zero data collected)

## What it is

- Native Apple TV client for **Jellyfin** servers
- **Jellyseerr** request flow built in — browse trending, request, track status, all on the TV
- Direct Play for HEVC / HEVC Main10 / AV1, HDR10, Dolby Vision, Dolby Atmos
- Custom FFmpeg + VideoToolbox engine, no VLCKit
- Open source, MIT — fork it, audit it, ship your own version

## Why open source

For the same reason you self-host Jellyfin in the first place. The other Apple TV options are closed-source binaries you have to trust. This one isn't.

The video engine ([AetherEngine](https://github.com/superuser404notfound/AetherEngine)) is LGPL-3.0 separately so it's reusable. The app shell on top is MIT.

## Tech stack for the curious

- SwiftUI + UIKit interop where needed
- AVSampleBufferDisplayLayer driven by a CMTimebase synced to audio
- Local HLS server in-process to wrap EAC3+JOC into Dolby MAT 2.0 for Atmos passthrough through AVPlayer
- Demux via FFmpeg (LGPL build, dynamic-linkable for App Store compliance), decode via VideoToolbox
- Keychain for credentials, UserDefaults for preferences, nothing leaves the device

## Beta status

This is the first public TestFlight. Internal testing has been running for a while; smoke tests pass; HDR + Atmos work on my setup but I want feedback from more TVs / receivers.

Requirements: Apple TV 4K, tvOS 26+, your own Jellyfin server.

Bug reports welcome on GitHub.
```

---

### r/AppleTV

**Title:**
```
JellySeeTV — open-source native Jellyfin client for Apple TV is in public beta
```

**Body:**
```markdown
For the Jellyfin users in here: JellySeeTV is now in public TestFlight beta.

**Install:** https://testflight.apple.com/join/REPLACE_ME

Native tvOS app — proper transport bar, focus engine, HDR/Dolby Vision display switching, Dolby Atmos via EAC3+JOC passthrough. Built from scratch on SwiftUI plus a custom video engine, no VLCKit, no web view.

Plus first-class Jellyseerr integration if you use that — browse trending and request stuff directly from the couch.

**Requirements:** Apple TV 4K, tvOS 26+, your own Jellyfin server.

It's MIT-licensed and fully open source — code is at https://github.com/superuser404notfound/JellySeeTV. No telemetry, no analytics.

Feedback welcome — particularly on HDR/Dolby Vision behavior across different TV models and Atmos handling on various AVRs. Bug reports in GitHub.
```

## Step 3 — Optional: Mastodon / Bluesky

Short version (under 500 chars), good for a single post:

```
🧪 JellySeeTV — open-source native Jellyfin client for Apple TV with built-in Jellyseerr — is now in public TestFlight beta.

Direct Play, real HDR10 / Dolby Vision, real Dolby Atmos. MIT, no telemetry.

TestFlight: https://testflight.apple.com/join/REPLACE_ME
Source: https://github.com/superuser404notfound/JellySeeTV

Apple TV 4K + tvOS 26+ required.
```

## Step 4 — Optional: Hacker News „Show HN"

Apple-related Show HN posts can go either way on HN — it's worth a try if you want broader tech reach. Keep the title plain and factual; HN dislikes marketing language.

**Title:**
```
Show HN: JellySeeTV – open-source native Apple TV client for Jellyfin + Jellyseerr
```

**URL field:** `https://github.com/superuser404notfound/JellySeeTV`
**Text field:** (leave blank — HN convention for Show HN with a URL is empty body, the discussion follows)

If it gets traction, be ready to hang in the comments for a few hours — HN audience asks technical questions and rewards prompt, honest answers.

## Step 5 — After launch — what to watch

- **GitHub Issues:** primary feedback channel
- **TestFlight Feedback:** in-app screenshots + system info, viewable in App Store Connect → TestFlight → Feedback
- **Reddit comments:** answer technical questions, take feature requests as informal signal
- **Crash reports:** App Store Connect → TestFlight → Crashes (if any come in)

## Cadence

- **Day 0:** TestFlight approved → update README link, post pinned issue, post on r/jellyfin
- **Day 1-2:** post on r/selfhosted (+ r/AppleTV optional)
- **Day 3-7:** triage feedback, fix critical bugs, push new builds
- **After 2-3 weeks of stable use:** consider App Store Submission

Don't try to be everywhere on day 0 — Reddit appreciates posts that get answered, not posted-and-forgotten. Pace it.
