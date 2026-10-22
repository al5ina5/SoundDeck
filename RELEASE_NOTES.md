# SoundDeck 0.2.0 — Experimental

Automatic per-app discovery and an expandable CCSupport Control Center mixer, built/tested on iPad7,5 / iPadOS 17.7.8 / palera1n rootless / ElleKit 1.2.

## What changed

- Removed manual app enrollment: participating playback clients are discovered from live telemetry and gains persist by bundle ID.
- Added native-volume adapters for AudioQueue, AVPlayer, AVAudioPlayer and AVSampleBufferAudioRenderer; added AVAudioEngine PCM/output-provider support.
- Added experimental WebKit subprocess injection and coalition-based host attribution.
- Added a CCSupport mixer with per-app sliders/mute, master media volume, adaptive expanded layout and diagnostics.
- Added five native/framework fixture apps, separate Web Audio/media-element fixtures, automated on-device suites and package validation.
- Hardened service discovery and package lifecycle, including SpringBoard/user launchd domains, CC layout preservation and uninstall bypass.

## Device verification

On the stated test iPad: RemoteIO PCM gains at 20% / 80% measured about 0.20 / 0.80 with separate post-render observers; five fixture adapters ran concurrently; Web Audio PCM reached 0.349947 at 35% and mute reached zero; WebKit media-element AVPlayer volume reached 0.35 and mute zero; Control Center and UIKit actions reached the backend; watchdog, upgrade/uninstall recovery passed. See `docs/TESTING.md` and sanitized reports in `docs/reports/`.

## Limits

**Experimental, not universal or production-certified.** These are fixture tests on one device, not third-party app certification or human/acoustic listening confirmation. Safari and protected streaming were not tested. Physical route transitions, human touch/VoiceOver review, portrait orientation and multi-hour endurance remain unverified. Some app audio paths may be uncontrollable. No automatic ducking.

## Assets

- `com.alsinas.sounddeck_0.2.0_iphoneos-arm64.deb`: normal rootless package.
- `com.alsinas.sounddeck.tests_0.2.0_iphoneos-arm64.deb`: optional QA fixtures; not needed for the app.
- `SHA256SUMS`: artifact checksums.

Install through a rootless jailbreak package manager or `sudo dpkg -i …`. SoundDeck adds its CCSupport module when possible. There is no enrollment step. Emergency bypass is `sdctl disable`; removal is `sudo apt remove com.alsinas.sounddeck.tests com.alsinas.sounddeck`.
