# Real-device validation — experimental 0.2.2

Tested directly on **iPad7,5 (iPad 6th generation), A10 arm64, iPadOS 17.7.8 (21H440), rootless palera1n / Procursus / ElleKit 1.2**, October 22, 2026. Compilation, signing, packaging, installation and tests were performed on-device.

0.2.2 adds a tap-to-open recovery/settings sheet and moves service snapshots off the main queue while keeping the audio runtime unchanged from the 0.2.1/0.2.0 path. Core PCM, framework, WebKit and lifecycle figures below are retained from the 0.2.1 baseline; the new 0.2.2 settings and service checks are reported separately.

Reports: [RemoteIO integration](reports/integration.json) · [framework adapters](reports/media.json) · [WebKit](reports/web.json) · [UI/Control Center](reports/ui.json) · [recovery/settings](reports/settings.json) · [package lifecycle](reports/lifecycle.json).

## Audio evidence and what it means

Two QA apps render continuous 440 Hz and 880 Hz signals through direct RemoteIO callbacks. Each deliberately starts with a nonmixing playback category; SoundDeck enables playback mixing. Input/output PCM is measured in the injected callback and independently by each fixture's own Core Audio post-render observer. These numbers validate digital PCM before device output; they are not a microphone/loopback capture, acoustic loudness measurement or human listening result.

Additional fixture adapters were verified as follows:

- **AudioQueue:** actual parameter values tracked base 0.9 × app gain 0.4 = 0.36; base changed to 0.6 and actual became 0.24; mute set volume to 0.
- **AVPlayer and AVAudioPlayer:** actual native volume tracked 0.9 × 0.4 = 0.36, followed host base 0.6 to 0.24, and mute set volume to 0.
- **AVSampleBufferAudioRenderer:** actual volume tracked 0.9 × 0.4 = 0.36, followed the host base and mute.
- **AVAudioEngine:** at gain 0.6, service output/input RMS ratio was 0.600000; an independent post-render observer measured 0.033997 RMS versus service output 0.033967 RMS. Mute output was zero while input continued.
- **WebKit Web Audio:** coalition attribution resolved the GPU subprocess to the fixture app; measured PCM output/input ratio was 0.349947 at 35%, and mute output was zero.
- **WebKit HTML media:** attributed GPU process reported AVPlayer native volume 0.35 at 35%; mute set it to zero.
- **Concurrency:** AudioQueue, AVPlayer, AVAudioPlayer, AVAudioEngine PCM and sample-buffer fixtures ran in five distinct app processes at different gains simultaneously.

Native-parameter tests prove the framework volume property/parameter SoundDeck writes and reads. They are not equivalent to independently measured acoustic output. WebKit results establish the fixture's paths only, not Safari or arbitrary pages/apps.

## Core PCM, watchdog and lifecycle

The latest integration run used a 30-second requested soak; the measured segment was 36.9 seconds. It passed concurrent 20%/80% playback, three cold-launch pairs, mute isolation/unmute, independent gain, 60 rapid gain/mute cycles, PID removal and preference restoration, backgrounding with the mixer foreground, dashboard restart, bypass/unity, re-enable and extended rendering. Measured PCM ratios were approximately 0.20 and 0.80. The service remained at one PID; reported CPU was 1.33% of one core and peak RSS 4,964,352 bytes for this run. This is not a multi-hour endurance or battery test.

The lifecycle suite passed service-loss watchdog recovery, package upgrade preserving enabled state/gains, actual SoundDeck uninstall restoring native session behavior/unity PCM, and reinstall. Service-loss/uninstall observer RMS was approximately 0.0564/0.0566 at unity. Package validation passed rootless paths, arm64 architecture, owners, Mach-O signatures/identity and absence of QA controls.

## UI and Control Center

The 0.2.1 UI suite drove real UIKit sliders (including zero-volume mute), checked backend gains, light/dark layout, icons, accessibility labels and compact card sizing. The Control Center suite opened/expanded the real CCSupport module, drove two app sliders, checked live backend changes and saved preferences, captured the module and verified dismissal. The system master-volume setter passed in 0.2.0; it was deliberately not changed during the 0.2.2 pass while user playback might be active. These are scripted control actions, not physical touch, animation or VoiceOver testing.

Portrait automation received the system error:

> The current windowing mode does not allow for programmatic changes to interface orientation.

Portrait is declared and adaptive layout code is present, but portrait remains unverified. Captures are native layer captures of SoundDeck's own view; they omit system chrome/live blur and do not show a physical Control Center screen.


## 0.2.2 recovery/settings and service checks

A tap (or VoiceOver custom action) on the master speaker icon opens a compact sheet with **Bypass/Enable**, **Reset volumes**, **Add/Remove from Control Center**, and **Diagnostics**. These are on-demand only; the normal dashboard remains icon-plus-slider rows.

- **Reset volumes:** with two fixture gains at 20%/30%, the sheet action restored both persisted gains to 1.0/1.0.
- **Bypass/enable:** the sheet toggled `disabled` in preferences and the service's global disabled state; re-enabling restored the enabled state.
- **Control Center recovery:** both the app action path and `sdctl cc-remove`/`cc-install` removed and restored only `com.alsinas.sounddeck.cc` in the CCSupport layout; the marker was restored.
- **Diagnostics:** the sheet reported backend version, active rows, process count and bypass state, with Copy/Done actions.
- **Service scan:** resolving paths and coalition identity only for fresh audio clients reduced a sampled snapshot from ~15 seconds to ~49 ms. The service now runs snapshots on a dedicated thread; the UI tolerates up to 20 seconds of scheduler delay rather than discarding active rows after 4 seconds.
- One UI automation attempt was interrupted by SpringBoard/Jetsam under load while launching a second fixture; it is recorded as an environment failure, not a pass.

## Real-app coverage

| App | Result |
|---|---|
| Apple Music | **Gain verified** on a non-personal station: 50.9% → 20%, native AVPlayer 0.509 → 0.20, restored. |
| Safari | **Gain verified** with the stock MP3: 80% → 40%, native AVPlayer 0.80 → 0.40, restored. |
| Music + Safari | **Not supported as simultaneous playback:** starting Safari stopped Music. A trial category-mix override did not fix it and was reverted. |
| Podcasts | Launched; onboarding/catalog content was not selected, so no audio path was verified. |
| TinyDodge / RayGame | Launched; no audible path was detected without game interaction. Not verified. |
| Photos / TV / Books / Files | Not exercised; no suitable non-personal media/library content was selected. |

## Interruption and route status

- Foreground/background and Control Center presentation were exercised without changing user media where possible.
- **Calls/Siri, screen lock, headphone jack, Bluetooth, AirPlay and physical route transitions were not tested.** The test session was paused at the user's request; these remain release blockers, not passes.
- The service-loss watchdog, package upgrade/uninstall and reinstall suites remain from the prior baseline. No 0.2.2 multi-hour soak is claimed.

## Accessibility and human QA

PSI accessibility inspection exposed app icons as non-interactive, sliders with app-specific labels/percent values, and the master icon with a settings custom action. Light/dark and compact card captures were inspected. **No human listening, VoiceOver speech review, physical touch review, full Dynamic Type range or portrait verification was completed.**

## Broader device/OS validation

Still limited to **iPad7,5 / iPadOS 17.7.8 / arm64**. No second device, arm64e process, iPadOS 15/16, or alternate rootless bootstrap was available. The package validator confirms rootless paths and arm64 Mach-O identity only; it does not establish runtime compatibility elsewhere.

## Optional PC-style concurrency research

The in-depth feasibility report is at [pc-style-concurrency-feasibility.md](research/pc-style-concurrency-feasibility.md). Verdict: public-API mixability is app- and timing-specific; a universal interruption suppressor would require private/daemon-level work and is **not recommended** for 0.2.x. No such feature ships.

## Live manual test result (PSI-controlled)

The `psi` utility (Psychosis) was used only for screen inspection and synthetic taps; it was not used to record or listen to audio. A non-personal Apple Music station (2010s Hip-Hop Essentials) was started in Music, and the included CC BY-SA piano MP3 was started in Safari.

- **Music gain:** while its AVPlayer was playing, the Music row changed from 50.9% to 20%; the reported native AVPlayer volume changed to 0.20 and returned to 0.509.
- **Safari gain:** with the stock MP3 playing, the Safari WebKit AVPlayer was attributed to Safari and changed from 80% to 40% (reported native volume 0.40), then restored to 80%.
- **Overlap limitation:** starting Safari while Music was playing caused Music to leave the active service rows. A trial build that forced `MixWithOthers` through `AVAudioSession` category hooks did not make both continue, so that unproven override was reverted and is not in the released package. This is app/session interruption behavior; SoundDeck does not suppress interruption notifications.
- The installed RayGame build did not begin audible playback without game interaction, so a three-app overlap was not established.

This establishes **independent gain control of Safari and Music when each is playing**, but **does not establish simultaneous Music + Safari playback** on this device/build. No PC-style forced-audio claim is made.

The included CC BY-SA 4.0 piano MP3 and Safari page remain in `Tests/assets/` for repeatable manual testing. A user can play the file directly in Safari; importing the MP3 into Apple Music requires a separate library import/sync.

## Not verified

No human listening or acoustic measurement; Podcasts/Photos/TV/Books/Files and commercial/DRM apps were not verified. Headphones/Bluetooth/AirPlay, incoming calls/Siri, screen-lock recovery, physical touch/VoiceOver, full Dynamic Type, Split View/Slide Over, portrait and multi-hour endurance remain unverified. The release is still **experimental**. See [compatibility](COMPATIBILITY.md).
