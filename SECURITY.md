# Security Policy

## Reporting a Vulnerability

If you find a security issue in JellySeeTV, please **do not** open a public GitHub issue.

Instead, email **superuser404@tuta.com** with:

- A short description of the issue
- Reproduction steps if you have them
- The version (Settings → bottom of the screen) and tvOS version

I'll respond as quickly as possible. For confirmed issues a fix typically lands within a few days, faster if it's exploitable in the wild.

## Scope

In scope:

- The JellySeeTV app code in this repository
- Anything that could leak credentials, tokens, or local files
- Crashes or undefined behaviour reachable from a malicious server response
- The accompanying [AetherEngine](https://github.com/superuser404notfound/AetherEngine) media engine

Out of scope:

- Vulnerabilities in **Jellyfin** itself — report to the [Jellyfin project](https://github.com/jellyfin/jellyfin/security)
- Vulnerabilities in **Seerr** / Jellyseerr — report to that project
- Issues in **FFmpeg** or upstream codec libraries — report to those projects
- Configuration mistakes on your own server (e.g. exposing Jellyfin without TLS)

## What you can expect

- Acknowledgement within 72 hours
- Disclosure timeline coordinated with you — typically 30 days from fix release before public details
- Credit in the release notes if you'd like (or anonymous if you prefer)

## What I can't promise

This is a hobby project maintained by one person. I can't pay bug bounties, and turnaround on lower-severity issues may be slower than you'd see at a funded project. Critical issues (RCE, credential exfiltration) are always top priority.

Thanks for helping keep JellySeeTV safe.
