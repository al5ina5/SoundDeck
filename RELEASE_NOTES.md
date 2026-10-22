# SoundDeck 0.2.1 — Experimental

Minimal per-app mixer UI refresh for rootless iPadOS. Tested on iPad7,5 / iPadOS 17.7.8 / palera1n rootless / ElleKit 1.2.

## Changes

- Reduced the app and Control Center to one horizontal icon + slider per active app, plus one icon + slider for system media volume.
- Removed app names, status copy, percentages, saved/inactive rows, explanatory panels and visible mute buttons. Slider zero is mute; VoiceOver labels retain app/system names and values.
- The app now uses a compact centered card sized to the active rows. Light/dark system colors keep the master glyph legible; Control Center icons are white for its dark platter.
- Added the CC BY-SA 4.0 piano test MP3 and a minimal Safari test page under `Tests/assets/`; neither is installed in the Music library or package.

## Verification and limits

- UIKit and Control Center slider actions, zero-volume mute, active-row filtering, compact layout, persistence and CC dismissal passed on-device.
- Safari's WebKit AVPlayer was started with the stock MP3 and attributed to Safari; its row changed 80% → 40% and restored, with the reported native AVPlayer volume matching.
- Music was tested with a non-personal Apple Music station: while playing, its row changed 50.9% → 20% and restored, with the native AVPlayer volume matching. Starting Safari while Music played caused Music to stop/leave the active rows. A trial `MixWithOthers` category-force build did not solve this and was reverted before packaging.
- This is therefore **not** a PC-style guarantee that all apps continue playing. The installed game did not play without game interaction. A local MP3 cannot be added to Music's library through this environment; import/sync it yourself for Music-library testing.
- The current UI run intentionally skipped master-volume mutation while user playback might be active. Previous 0.2.0 master set/restore checks passed. Independent gain control of Safari and Music was verified; simultaneous audible playback was not.

Still experimental: one test device; no broad third-party/DRM certification, human-listening signoff, physical route-transition test, portrait validation or multi-hour endurance claim.

## Assets

- `com.alsinas.sounddeck_0.2.1_iphoneos-arm64.deb`: normal rootless package.
- `com.alsinas.sounddeck.tests_0.2.1_iphoneos-arm64.deb`: optional QA fixtures.
- `SHA256SUMS`: release artifact checksums.
