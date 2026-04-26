# JellySeeTV Beta — for testers

Thanks for testing JellySeeTV. This page tells you how to get the build, what to look at, and how to report what you find.

## What JellySeeTV is

A native Apple TV media player for your own Jellyfin server, with built-in [Seerr](https://github.com/Fallenbagel/jellyseerr) browse + request flow. Direct Play, real HDR10 / Dolby Vision, real Dolby Atmos. Open source ([GPL-3.0 with App Store Exception](LICENSE)), no telemetry.

For the long pitch see the [README](README.md).

## What you need

- **Apple TV 4K** (any generation) running **tvOS 26.0 or later**
- A **Jellyfin server** you can reach from the Apple TV (10.9+ recommended)
- *Optional:* a **Seerr / Jellyseerr** instance (2.0+) if you want to test the request flow
- An **Apple ID** signed in on your Apple TV (no invite required — this is a public beta)

## Install the build

1. On any device signed in with your Apple ID, open the public TestFlight link: **https://testflight.apple.com/join/eFKDaaXr**
2. Tap **Accept** and **Install** — TestFlight handles the rest
3. On your Apple TV, install the **TestFlight** app from the App Store if it isn't already there
4. Sign in with the same Apple ID; **JellySeeTV** appears in the list — tap **Install**
5. Open it from the home screen

If it tells you "this beta has expired", revisit the join link above to grab the current build — TestFlight builds expire after 90 days.

## What to test

The high-value areas — what we most want feedback on:

### Setup & connection
- Server discovery (auto + manual)
- Login with username + password, with and without Quick Connect
- Reconnecting after the app comes back from background

### Browsing
- Home customization (Continue Watching, Next Up, Latest, custom rows)
- Series detail view — switch seasons, scroll long episode lists
- Search — both your library and the Seerr catalog (when Seerr is connected)

### Playback
- A regular SDR movie
- An HDR10 / Dolby Vision movie if you have one — does the TV switch into HDR mode? Does the picture look right?
- An EAC3+JOC (Atmos) stream if you have one — does your AVR's Atmos light come on?
- Track switching mid-playback (audio language, subtitle language)
- Resume from where you stopped, on multiple devices
- Auto-play next episode for series

### Seerr integration
- Browse trending / popular
- Request a movie or series
- Status display for what you've requested

### Edge cases
- Slow Wi-Fi
- Multiple Apple TVs on the same Jellyfin account
- Going to background mid-playback (Siri Remote home button) and coming back

## How to report a bug

Open an issue on GitHub: **<https://github.com/superuser404notfound/JellySeeTV/issues/new/choose>**

Please include:

1. **What you did** — exact steps
2. **What you expected**
3. **What actually happened**
4. **Build version** — Settings → scroll to the bottom, e.g. `0.1.0 (1)`
5. **tvOS version** — Settings on the Apple TV → System → About
6. **Jellyfin server version** if relevant
7. **A photo of the screen** if it's a visual bug — taking a screenshot from the Siri Remote (`TV` + `Play/Pause`) lands the file on your Mac via Photos
8. *Optional:* TestFlight Feedback (long-press in the TestFlight app) attaches a screenshot + system info automatically — also fine

Bugs already known live in the [open issues](https://github.com/superuser404notfound/JellySeeTV/issues) — search before filing a duplicate.

## What you should NOT expect from a beta

- **Crashes are possible** — Apple TV won't be damaged, but you may have to relaunch
- **Some features may be incomplete** — for example, HDR display switching depends on TV model + the Match Content setting
- **TestFlight builds expire after 90 days** — you'll get a new invite when a fresh build lands
- **Your watch progress is stored on your Jellyfin server**, not in the app — if you reinstall you keep all your progress

## Privacy reminder

JellySeeTV does not collect, transmit, or share any usage data. Everything stays between your Apple TV and the servers you point it at. Full details: <https://jellyseetv.superuser404.de/privacy>.

## Thanks

If something feels off, tell us. If something feels good, also tell us — both kinds of feedback help.
