# 📺 JellySeeTV

A native Jellyfin client for Apple TV, built with SwiftUI and [SteelPlayer](https://github.com/superuser404notfound/SteelPlayer).

[![Platform](https://img.shields.io/badge/platform-tvOS%2016%2B-black)]()
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)]()

## About

JellySeeTV brings your Jellyfin media server to Apple TV with a native tvOS experience. Built from the ground up with SwiftUI and a custom FFmpeg + Metal video engine, it supports direct playback of virtually any format — including 4K HEVC, HDR10, Dolby Vision, and Dolby Atmos — without server-side transcoding.

## Screenshots

*Coming soon*

## Features

### Media Browsing
- [x] Server discovery (manual + automatic)
- [x] User authentication with Jellyfin API
- [x] Library browsing (Movies, Series, Collections)
- [x] Movie detail view with metadata, cast, and tech info
- [x] Series detail view with season/episode navigation
- [x] Continue Watching / Next Up
- [x] Search
- [x] Image caching and prefetching

### Player
- [x] Custom FFmpeg + Metal engine ([SteelPlayer](https://github.com/superuser404notfound/SteelPlayer))
- [x] Hardware-accelerated H.264 / HEVC decoding via VideoToolbox
- [x] Direct Play for all supported codecs (no server transcoding)
- [x] MKV container support (via Jellyfin container remux)
- [x] Native tvOS player UI (transport bar, scrubbing, title overlay)
- [x] Siri Remote support (touch surface scrubbing, click, play/pause, ±10s skip)
- [x] Jellyfin session reporting (start, progress, stop)
- [x] Resume playback from last position
- [ ] HDR10 / Dolby Vision playback with tone mapping *(Phase 4)*
- [ ] Audio output with multichannel + Atmos *(Phase 2)*
- [ ] A/V synchronization *(Phase 2)*
- [ ] Subtitle support (SRT, SSA, PGS) *(Phase 6)*
- [ ] Audio / subtitle track selection UI *(Phase 2/6)*

### Seerr Integration *(Planned)*
- [ ] Browse trending / popular media
- [ ] Request movies and series
- [ ] View request status

### Design
- [x] Dark minimalistic design
- [x] Localized in 15 languages (DE, EN, ES, FR, IT, JA, KO, NL, PL, RU, SV, NB, DA, ZH-Hans, PT-BR)
- [ ] Liquid Glass design language *(tvOS 26+)*

## Architecture

```
JellySeeTV
├── App/                    App entry point, navigation, authentication
├── Features/
│   ├── Home/               Continue Watching, Latest, Libraries
│   ├── Detail/             Movie + Series detail views
│   ├── Search/             Search interface
│   └── Settings/           Server config, preferences
├── Player/
│   ├── Engine/             SteelPlayer integration + AVPlayer fallback
│   ├── UI/                 TransportBar, RemoteTapHandler, MetalVideoView
│   ├── PlayerView.swift    Main player screen
│   ├── PlayerViewModel.swift  State management + Jellyfin reporting
│   ├── DirectPlayProfile.swift  Codec capability detection
│   └── DisplayCapabilities.swift  HDR display detection
├── Services/
│   └── Jellyfin/           API client, endpoints, playback service
├── Models/                 Data models (JellyfinItem, MediaStream, etc.)
└── Components/             Reusable UI components
```

## Building

### Requirements

- Xcode 26+
- tvOS 16.0+ deployment target
- Apple TV 4K (for testing)
- A Jellyfin server on your network

### Steps

1. Clone the repository
   ```bash
   git clone https://github.com/superuser404notfound/JellySeeTV.git
   ```

2. Open in Xcode
   ```bash
   open JellySeeTV.xcodeproj
   ```

3. Select the `JellySeeTV` scheme and an Apple TV target

4. Build and run (⌘R)

> **Note:** SteelPlayer (the video engine) is included as a local Swift Package dependency.

## Roadmap

### Player Engine ([SteelPlayer](https://github.com/superuser404notfound/SteelPlayer))

- [x] Phase 0 — Package skeleton + FFmpeg dependency
- [x] Phase 1 — Demuxer + VideoToolbox decoder + Metal renderer
- [ ] Phase 2 — Audio output + A/V synchronization
- [ ] Phase 3 — Keyframe-accurate seeking
- [ ] Phase 4 — HDR10 / Dolby Vision tone mapping
- [ ] Phase 5 — Stability + edge cases
- [ ] Phase 6 — Subtitle rendering
- [ ] Phase 7 — App Store readiness

### App Features

- [x] Jellyfin browsing + authentication
- [x] Movie + Series detail views
- [x] Basic video playback (SDR content)
- [ ] Full video playback (all formats, HDR, audio)
- [ ] Seerr integration
- [ ] Liquid Glass UI refresh
- [ ] TestFlight beta
- [ ] App Store release

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI Framework | SwiftUI |
| Video Engine | [SteelPlayer](https://github.com/superuser404notfound/SteelPlayer) (FFmpeg + Metal) |
| Video Decode | VideoToolbox (hardware-accelerated) |
| Video Render | Metal (CAMetalLayer) |
| Audio | AVSampleBufferAudioRenderer |
| Networking | URLSession + Jellyfin REST API |
| Media Server | [Jellyfin](https://jellyfin.org) |

## Related Projects

- [SteelPlayer](https://github.com/superuser404notfound/SteelPlayer) — The open-source video engine powering JellySeeTV
- [Jellyfin](https://github.com/jellyfin/jellyfin) — The free software media system
- [Swiftfin](https://github.com/jellyfin/Swiftfin) — Official Jellyfin client for iOS/tvOS (VLCKit-based)

## License

*License TBD — will be determined before App Store release.*
