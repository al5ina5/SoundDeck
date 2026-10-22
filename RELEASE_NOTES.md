# SoundDeck 0.2.2 — Experimental

Minimal per-app mixer UI refresh for rootless iPadOS. Tested on iPad7,5 / iPadOS 17.7.8 / palera1n rootless / ElleKit 1.2.

## Changes

- Reduced the app and Control Center to one horizontal icon + slider per active app, plus one icon + slider for system media volume.
- Removed app names, status copy, percentages, saved/inactive rows, explanatory panels and visible mute buttons. Slider zero is mute; VoiceOver labels retain app/system names and values.
- The app now uses a compact centered card sized to the active rows. Light/dark system colors keep the master glyph legible; Control Center icons are white for its dark platter.
- Added the CC BY-SA 4.0 piano test MP3 and a minimal Safari test page under `Tests/assets/`; neither is installed in the Music library or package.
- Added on-demand recovery/settings access: tap the master speaker icon for Bypass/Enable, Reset volumes, Control Center add/remove and Diagnostics. No extra always-visible controls were added.
- Moved service snapshots to a dedicated thread, limited path/coalition resolution to fresh audio clients, and widened the UI freshness window so a busy iPad does not drop active rows. A sampled discovery snapshot fell from about 15 seconds to 49 ms.
- Added the optional PC-style concurrency feasibility report at `docs/research/pc-style-concurrency-feasibility.md`; no forced-concurrency feature ships.

## Verification and limits

- UIKit and Control Center slider actions, zero-volume mute, active-row filtering, compact layout, persistence and CC dismissal passed in the 0.2.1 baseline.
- 0.2.2 settings actions were exercised through the real sheet: reset restored 20%/30% gains to 100%, bypass/enable toggled the service state, Diagnostics displayed, and Control Center add/remove changed only SoundDeck’s module entry.
- Safari's WebKit AVPlayer was started with the stock MP3 and attributed to Safari; its row changed 80% → 40% and restored, with the reported native AVPlayer volume matching.
- Music was tested with a non-personal Apple Music station: while playing, its row changed 50.9% → 20% and restored, with the native AVPlayer volume matching. Starting Safari while Music played caused Music to stop/leave the active rows. A trial `MixWithOthers` category-force build did not solve this and was reverted before packaging.
- This is therefore **not** a PC-style guarantee that all apps continue playing. The installed game did not play without game interaction. A local MP3 cannot be added to Music's library through this environment; import/sync it yourself for Music-library testing.
- One 0.2.2 UI automation attempt was interrupted by SpringBoard/Jetsam under load while launching a second fixture; it is not counted as a pass.
- Podcasts, Photos, TV, Books and Files were not verified with non-personal media. Calls/Siri, screen lock, headphones/Bluetooth/AirPlay and physical route transitions remain untested. Independent gain control of Safari and Music was verified; simultaneous audible playback was not.

Still experimental: one test device; no broad third-party/DRM certification, human-listening signoff, physical route-transition test, portrait validation or multi-hour endurance claim.

## Assets

- `com.alsinas.sounddeck_0.2.2_iphoneos-arm64.deb`: normal rootless package.
- `com.alsinas.sounddeck.tests_0.2.2_iphoneos-arm64.deb`: optional QA fixtures.
- `SHA256SUMS`: release artifact checksums.
