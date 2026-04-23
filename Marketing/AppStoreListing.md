# JellySeeTV — App Store Connect Listing

Drafts for App Store Connect. Copy-paste into the matching fields.

**Versioning convention used here:**
- `0.x.y` covers the entire TestFlight Beta phase. Both bugfixes and smaller features land here. Patch (`0.1.x`) for bug-only, minor (`0.x.0`) when a feature ships during Beta.
- `1.0` is reserved for the first stable App Store release. It's a stability marker, not a feature marker — promoting the most recent Beta build to public.
- Larger new features wait until after `1.0` and ship as `1.1`, `1.2`, etc.
- Build number resets to `1` on every MARKETING_VERSION change, monotonically increases within a marketing version (Apple requirement).

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

JellySeeTV is the only open-source Apple TV client that brings Jellyfin and Seerr together in one native interface. Watch what's already on your server. See something on a trending row that isn't there yet? Request it from inside the app — Seerr handles the rest. No more switching to a phone, opening a web UI, or pinging your homelab admin.

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

### What's New (for 0.1.0)
```
JellySeeTV 0.1.0 is the first public TestFlight build.

Native Jellyfin client for Apple TV with built-in Seerr integration. Direct Play, real HDR10 / Dolby Vision, real Dolby Atmos. 26 languages. Open source.

This is a Beta release. Crashes and edge-case bugs are possible. Please report what you find: https://github.com/superuser404notfound/JellySeeTV/issues
```
(380 chars)

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

JellySeeTV ist der einzige Open-Source-Apple-TV-Client, der Jellyfin und Seerr in einer nativen Oberfläche vereint. Schau, was schon auf deinem Server liegt. Etwas in einer Trending-Reihe entdeckt, das noch nicht da ist? Fordere es direkt aus der App an — Seerr erledigt den Rest. Kein Wechsel ans Handy, kein Aufrufen von Web-UIs, kein Anpingen des Homelab-Admins.

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

### Was ist neu (für 0.1.0)
```
JellySeeTV 0.1.0 ist der erste öffentliche TestFlight-Build.

Nativer Jellyfin-Client für Apple TV mit eingebauter Seerr-Integration. Direct Play, echtes HDR10 / Dolby Vision, echtes Dolby Atmos. 26 Sprachen. Open Source.

Dies ist ein Beta-Release. Abstürze und Edge-Case-Bugs sind möglich. Bitte melde, was du findest: https://github.com/superuser404notfound/JellySeeTV/issues
```
(380 chars)

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
JellySeeTV is a media player for self-hosted Jellyfin servers. The app requires the user to point it at their own Jellyfin instance — there is no built-in content, no first-party servers, and no in-app purchases.                                                                                                                                                
   
To exercise the app, please use the official Jellyfin demo server, which is publicly available and intentionally provided for testing purposes:                                   
                                                         
    Server URL: https://demo.jellyfin.org/stable                                                                                                                                    
    Username:   demo                                     
    Password:   (leave empty — the demo account has no password)                                                                                                                    
                                                         
Steps to test:                                                                                                                                                                    
1. Launch the app. The Server Discovery screen appears.
2. Choose "Add Server Manually" (auto-discovery only finds servers on the local network, which is not the case here).                                                             
3. Enter the server URL above.                                                                                                                                                    
4. Enter the username "demo" and leave the password field empty.                                                                                                                  
5. The library loads. You can browse Movies, Series, search, open a detail view, and start playback.                                                                              
                                                                                                                                                                                    
The Jellyseerr (catalog/request) features and Dolby Atmos passthrough cannot be exercised against the demo server, as it does not have those services configured. Apart from that,
the full app flow is testable.                                                                                                                                                   
                                                                                                                                                                                    
If the demo server is unreachable for any reason, please contact superuser404@tuta.com and I will provide temporary credentials to a private Jellyfin instance for review         
purposes.
                                                                                                                                                                                    
Additional notes:                                      
  - The app collects no user data. The Privacy Manifest in the bundle confirms zero tracking and zero data collection.
  - All credentials entered by the user are stored in the system Keychain only.                                                                                                     
  - Source code is publicly auditable at https://github.com/superuser404notfound/JellySeeTV
  - The video engine (FFmpeg + VideoToolbox + AVPlayer) is split into a separate LGPL-3.0 package: https://github.com/superuser404notfound/AetherEngine                             

Thank you for reviewing.
```


### 

- **First Name:** Vincent
- **Last Name:** Herbst
- **Phone:** *(your number, optional but speeds up review contact)*
- **Email:** superuser404@tuta.com

---

## Notes on Translations

- The 24 languages beyond EN/DE are **not** required for App Store listing localization at launch. Apple shows the app in the user's preferred language if available, otherwise falls back to the primary listing.
- Adding more localizations later is non-breaking — can be done at any time without resubmission.
- The **app's UI** is localized in all 26 languages (separately from the App Store listing).



TEST TEXT ----- 


Welcome to JellySeeTV — public beta!                                                                                                                                        
                                                                                
JellySeeTV is a native Apple TV client for self-hosted Jellyfin servers, with built-in Seerr/Jellyseerr integration for browsing and requesting media. Direct Play, real HDR10 /  
Dolby Vision, real Dolby Atmos. Open source (MIT).                            
                                                                                                                                                                                    
Note for Apple Reviewer: this app requires a Jellyfin server, which the user must self-host.
Without server access the login screen, server discovery flow and error handling can 
still be exercised. If a working test environment is needed, please contact superuser404@tuta.com
for temporary read-only credentials to a private Jellyfin instance.
                                                                                                                                                                                    
  What to focus on for this build:                                                                                                                                                  
  • Server discovery + login (auto-discovery on the local network, plus manual URL entry)                                                                                           
  • Browsing — Home, Library, Series detail, Search across both library and Seerr catalog                                                                                           
  • Playback — Direct Play across codecs, HDR display switching, Dolby Atmos passthrough, audio/subtitle track switching                                                            
  • Seerr integration — browse trending, request a movie or series, status display                                                                                                  
  • Resume + auto-play next episode for series                                                                                                                                      
                                                                                                                                                                                    
Known limitations: HDR display switching depends on the TV model and the Match Content setting.
TestFlight builds expire after 90 days.                                           
                                                                                
Full tester guide and how to file bugs: https://github.com/superuser404notfound/JellySeeTV/blob/main/BETA.md                                                                      
                                                                                                                                                                                    
Source code: https://github.com/superuser404notfound/JellySeeTV
