# JellySeeTV — App Store Connect Listing

Drafts for App Store Connect. Copy-paste into the matching fields.

**Versioning convention used here:**
- Marketing version: `1.0.0`
- Build number: `1` (TestFlight build #1)

**Limits Apple enforces:**

| Field | Max length |
|---|---|
| Name | 30 chars |
| Subtitle | 30 chars |
| Promotional Text | 170 chars |
| Description | 4000 chars |
| Keywords (total, comma-separated) | 100 chars |
| What's New | 4000 chars |

---

## English (Primary)

### Name
```
JellySeeTV
```
(10 chars)

### Subtitle
```
Jellyfin + Seerr on your TV
```
(27 chars)

### Promotional Text
```
Watch your Jellyfin library and request what's missing from the same app. Native tvOS, real HDR, real Dolby Atmos. Open source, no telemetry.
```
(143 chars)

### Description
```
Your Jellyfin library and Seerr — together on Apple TV.

JellySeeTV is the only Apple TV client that brings Jellyfin and Seerr together in one native interface. Watch what's already on your server. See something on a trending row that isn't there yet? Request it from inside the app — Seerr handles the rest. No more switching to a phone, opening a web UI, or pinging your homelab admin.

WATCH
• Direct Play for almost every codec your Apple TV understands: H.264, HEVC, HEVC Main10, AV1
• HDR10, Dolby Vision and HLG — auto-detected, sent through with full color metadata, display switches to HDR mode automatically (Match Content)
• Dolby Atmos via EAC3+JOC, wrapped as Dolby MAT 2.0 — your AVR's Atmos light actually comes on
• Multichannel surround — 5.1 and 7.1 with correct channel layout
• Resume from where you left off, on any device
• Auto-detected intro skip with optional one-tap or auto-skip
• Next-episode autoplay with configurable countdown
• Subtitle support (SRT) with mid-playback track switching
• Audio track switcher — pick the language or surround mix you want, mid-playback
• Native tvOS player UI — same transport bar, scrub preview and info panel as Apple TV+

REQUEST WHAT'S MISSING
• First-class Seerr integration — browse trending and popular media inside the app
• One-tap requests for movies and full series
• Track status — see what's been approved, declined, or is already downloading
• Single sign-on — log in once, JellySeeTV handles your Seerr session

PERSONAL
• 26 languages — German, English, Spanish, French, Italian, Japanese, Korean, Norwegian, Dutch, Polish, Portuguese (BR + PT), Russian, Swedish, Simplified + Traditional Chinese, Turkish, Ukrainian, Czech, Slovak, Croatian, Finnish, Greek, Hungarian, Romanian, Danish
• Dark, minimal design — built for living rooms, not for desks
• Liquid Glass UI accents on tvOS 26+
• Siri Remote optimized — touch surface scrubbing, click for play/pause, swipe gestures throughout

OPEN SOURCE, END TO END
JellySeeTV is MIT licensed; the underlying video engine, AetherEngine, is LGPL-3.0. No telemetry. No analytics. No third-party SDKs phoning home. Self-host the server, audit the client.

REQUIREMENTS
• Apple TV 4K (any generation)
• tvOS 26.0 or later
• Your own Jellyfin server (10.9+ recommended)
• Optional: a Seerr instance (2.0+) for in-app requests

Source code, issues, and roadmap on GitHub:
https://github.com/superuser404notfound/JellySeeTV
```
(2378 chars — well under 4000)

### Keywords
```
jellyfin,seerr,jellyseerr,media,player,hdr,dolby,atmos,4k,homelab,plex,emby
```
(76 chars)

*Notes:*
- `jellyseerr` included as alias since it was the previous brand name and people still search for it
- `plex,emby` for competitive discovery (users searching alternatives find JST)

### What's New (for 1.0.0)
```
Welcome to JellySeeTV — the first release.

Native Jellyfin client for Apple TV with built-in Seerr integration. Direct Play, real HDR10 / Dolby Vision, real Dolby Atmos. 26 languages. Open source.

Spotted a bug or want to request a feature? GitHub issues are open:
https://github.com/superuser404notfound/JellySeeTV/issues
```
(327 chars)

### Support URL
```
https://github.com/superuser404notfound/JellySeeTV/issues
```

### Marketing URL (optional)
```
https://jellyseetv.superuser404.de
```

### Privacy Policy URL
```
https://jellyseetv.superuser404.de/privacy
```

### Category
- **Primary:** Entertainment
- **Secondary:** Lifestyle

### Age Rating
- 4+ (no objectionable content from JST itself; user-supplied media is the user's responsibility)

---

## Deutsch (Sekundär-Localization)

### Name
```
JellySeeTV
```

### Untertitel
```
Jellyfin + Seerr auf deinem TV
```
(30 chars — am Limit)

### Werbetext
```
Schau deine Jellyfin-Bibliothek und fordere fehlendes aus derselben App an. Nativ für tvOS, echtes HDR, echtes Dolby Atmos. Open Source, keine Telemetrie.
```
(157 chars)

### Beschreibung
```
Deine Jellyfin-Bibliothek und Seerr — gemeinsam auf Apple TV.

JellySeeTV ist der einzige Apple-TV-Client, der Jellyfin und Seerr in einer nativen Oberfläche vereint. Schau, was schon auf deinem Server liegt. Etwas in einer Trending-Reihe entdeckt, das noch nicht da ist? Fordere es direkt aus der App an — Seerr erledigt den Rest. Kein Wechsel ans Handy, kein Aufrufen von Web-UIs, kein Anpingen des Homelab-Admins.

SCHAUEN
• Direct Play für nahezu jedes Codec, das dein Apple TV unterstützt: H.264, HEVC, HEVC Main10, AV1
• HDR10, Dolby Vision und HLG — automatisch erkannt und mit vollständigen Farb-Metadaten übergeben, das Display schaltet automatisch in den HDR-Modus (Match Content)
• Dolby Atmos via EAC3+JOC, eingepackt als Dolby MAT 2.0 — die Atmos-Anzeige deines Receivers leuchtet tatsächlich auf
• Mehrkanal-Surround — 5.1 und 7.1 mit korrekter Kanal-Anordnung
• Fortsetzen, wo du aufgehört hast — auf jedem Gerät
• Automatisch erkannter Intro-Skip, optional per Knopfdruck oder automatisch
• Autoplay für die nächste Episode mit konfigurierbarem Countdown
• Untertitel-Unterstützung (SRT), umschaltbar während der Wiedergabe
• Audio-Track-Wechsler — wähle Sprache oder Surround-Mix mitten in der Wiedergabe
• Native tvOS-Player-UI — gleiche Transport-Leiste, Scrub-Vorschau und Info-Panel wie bei Apple TV+

FEHLENDES ANFORDERN
• Erstklassige Seerr-Integration — Trends und beliebte Inhalte direkt in der App durchstöbern
• Filme und ganze Serien mit einem Tap anfordern
• Status verfolgen — sehe, was genehmigt, abgelehnt oder bereits am Herunterladen ist
• Single Sign-On — einmal anmelden, JellySeeTV verwaltet deine Seerr-Session

PERSÖNLICH
• 26 Sprachen — Deutsch, Englisch, Spanisch, Französisch, Italienisch, Japanisch, Koreanisch, Norwegisch, Niederländisch, Polnisch, Portugiesisch (BR + PT), Russisch, Schwedisch, Vereinfachtes + Traditionelles Chinesisch, Türkisch, Ukrainisch, Tschechisch, Slowakisch, Kroatisch, Finnisch, Griechisch, Ungarisch, Rumänisch, Dänisch
• Dunkles, minimalistisches Design — gemacht für Wohnzimmer, nicht für Schreibtische
• Liquid-Glass-UI-Akzente auf tvOS 26+
• Optimiert für die Siri Remote — Scrubbing über die Touch-Fläche, Klick für Play/Pause, Wisch-Gesten überall

OPEN SOURCE, KOMPLETT
JellySeeTV ist unter MIT lizenziert; die zugrundeliegende Video-Engine AetherEngine unter LGPL-3.0. Keine Telemetrie. Keine Analytik. Keine Drittanbieter-SDKs, die nach Hause telefonieren. Selbst hosten, selbst auditieren.

VORAUSSETZUNGEN
• Apple TV 4K (jede Generation)
• tvOS 26.0 oder neuer
• Eigener Jellyfin-Server (10.9+ empfohlen)
• Optional: eine Seerr-Instanz (2.0+) für Anfragen aus der App heraus

Quellcode, Issues und Roadmap auf GitHub:
https://github.com/superuser404notfound/JellySeeTV
```
(2459 chars)

### Keywords (DE)
```
jellyfin,seerr,jellyseerr,medienspieler,heimkino,hdr,dolby,atmos,4k,homelab,plex,emby
```
(86 chars)

### Was ist neu (für 1.0.0)
```
Willkommen bei JellySeeTV — das erste Release.

Nativer Jellyfin-Client für Apple TV mit eingebauter Seerr-Integration. Direct Play, echtes HDR10 / Dolby Vision, echtes Dolby Atmos. 26 Sprachen. Open Source.

Bug entdeckt oder Feature-Wunsch? GitHub-Issues sind offen:
https://github.com/superuser404notfound/JellySeeTV/issues
```
(322 chars)

### Support-URL
```
https://github.com/superuser404notfound/JellySeeTV/issues
```

### Marketing-URL (optional)
```
https://jellyseetv.superuser404.de
```

### Datenschutz-URL
```
https://jellyseetv.superuser404.de/privacy
```

---

## App Privacy (Data Collection Disclosure)

In App Store Connect → App Privacy:

**Question: Does your app collect data?**
→ **No, we do not collect data from this app**

(JellySeeTV does not collect, transmit, or share any user data. The Privacy Manifest in the bundle confirms this. Communication only with the user's own self-hosted Jellyfin/Seerr servers.)

---

## Beta App Review Information (TestFlight)

When the build goes for **External** TestFlight (Internal Testing skips review), Apple needs:

### Sign-In Required?
→ **Yes** (the app requires signing into a Jellyfin server)

### Demo Account / Test Notes
```
JellySeeTV is a media player for self-hosted Jellyfin servers. Apple's reviewers cannot sign into the user's private server, but the app's startup, authentication UI, and core navigation can be exercised without playback by:

1. Launching the app — the server discovery / login screen appears immediately
2. Tapping "Add Server Manually" — the URL/credentials input UI shows
3. The app gracefully handles invalid server URLs and shows a clear error

If a working test environment is required, we can provide temporary read-only credentials to a private Jellyfin instance — please contact superuser404@tuta.com for access.

The app contains no in-app purchases, no advertising, no telemetry, and no user tracking. Source code is publicly auditable at https://github.com/superuser404notfound/JellySeeTV
```

### Contact Information
- **First Name:** Vincent
- **Last Name:** Herbst
- **Phone:** *(your number, optional but speeds up review contact)*
- **Email:** superuser404@tuta.com

---

## Notes on Translations

- The 24 languages beyond EN/DE are **not** required for App Store listing localization at launch. Apple shows the app in the user's preferred language if available, otherwise falls back to the primary listing.
- Adding more localizations later is non-breaking — can be done at any time without resubmission.
- The **app's UI** is localized in all 26 languages (separately from the App Store listing).
