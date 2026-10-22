# SoundDeck 0.1.0 — Experimental

Native rootless iPad audio mixer, built and tested on iPad7,5 / iPadOS 17.7.8 / palera1n / ElleKit 1.2.

## Verified

- Two separate RemoteIO signal applications render simultaneously at independent 20% / 80% PCM levels.
- Per-app mute isolation, preference persistence, repeated cold launches, UI actions and background playback.
- Native master media-volume action and light/dark dashboard captures.
- Approximately three-minute extended segment, service-loss bypass, package upgrade and actual uninstall/reinstall recovery.
- Normal package architecture/signing identity/rootless paths validated; no QA UI hooks in normal app.

## Important limits

**Not production-ready or universal.** Verified audio support is the direct mono Float32 RemoteIO callback path. AVPlayer is experimental/unverified. AudioQueue, general AVAudioEngine graphs, Safari/WebKit attribution, DRM and arbitrary third-party apps are unsupported/unverified. Physical routes, human listening, portrait in the current windowing mode and multi-hour stability remain unverified. No automatic ducking.

Read `docs/COMPATIBILITY.md` and `docs/TESTING.md` before installing. Numeric PCM tests are not acoustic listening confirmation.

## Assets

- `com.alsinas.sounddeck_0.1.0_iphoneos-arm64.deb`: normal native app, allowlisted tweak, service and CLI.
- `com.alsinas.sounddeck.tests_0.1.0_iphoneos-arm64.deb`: optional quiet 440/880 Hz verification applications.
- `SHA256SUMS`: artifact checksums.

Install through a jailbreak package manager or `sudo dpkg -i …`. Enroll supported apps with **+**, then restart only those apps. Emergency bypass: `sdctl disable`. Removal: `sudo apt remove com.alsinas.sounddeck.tests com.alsinas.sounddeck`.
