# Real-device validation — experimental 0.2.1

Tested directly on **iPad7,5 (iPad 6th generation), A10 arm64, iPadOS 17.7.8 (21H440), rootless palera1n / Procursus / ElleKit 1.2**, October 22, 2026. Compilation, signing, packaging, installation and tests were performed on-device.

0.2.1 changes the app/Control Center UI and adds a licensed test asset; the audio runtime is unchanged from the 0.2.0 baseline. Core PCM and lifecycle figures are retained from that baseline; framework, WebKit and minimalist UI suites were rerun with 0.2.1.

Reports: [RemoteIO integration](reports/integration.json) · [framework adapters](reports/media.json) · [WebKit](reports/web.json) · [UI/Control Center](reports/ui.json) · [package lifecycle](reports/lifecycle.json).

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

The 0.2.1 UI suite drove real UIKit sliders (including zero-volume mute), checked backend gains, light/dark layout, icons, accessibility labels and compact card sizing. The Control Center suite opened/expanded the real CCSupport module, drove two app sliders, checked live backend changes and saved preferences, captured the module and verified dismissal. The system master-volume setter passed in 0.2.0; it was deliberately not changed during the 0.2.1 pass while user playback might be active. These are scripted control actions, not physical touch, animation or VoiceOver testing.

Portrait automation received the system error:

> The current windowing mode does not allow for programmatic changes to interface orientation.

Portrait is declared and adaptive layout code is present, but portrait remains unverified. Captures are native layer captures of SoundDeck's own view; they omit system chrome/live blur and do not show a physical Control Center screen.

## Live manual test result (PSI-controlled)

The `psi` utility (Psychosis) was used only for screen inspection and synthetic taps; it was not used to record or listen to audio. A non-personal Apple Music station (2010s Hip-Hop Essentials) was started in Music, and the included CC BY-SA piano MP3 was started in Safari.

- **Music gain:** while its AVPlayer was playing, the Music row changed from 50.9% to 20%; the reported native AVPlayer volume changed to 0.20 and returned to 0.509.
- **Safari gain:** with the stock MP3 playing, the Safari WebKit AVPlayer was attributed to Safari and changed from 80% to 40% (reported native volume 0.40), then restored to 80%.
- **Overlap limitation:** starting Safari while Music was playing caused Music to leave the active service rows. A trial build that forced `MixWithOthers` through `AVAudioSession` category hooks did not make both continue, so that unproven override was reverted and is not in the released package. This is app/session interruption behavior; SoundDeck does not suppress interruption notifications.
- The installed RayGame build did not begin audible playback without game interaction, so a three-app overlap was not established.

This establishes **independent gain control of Safari and Music when each is playing**, but **does not establish simultaneous Music + Safari playback** on this device/build. No PC-style forced-audio claim is made.

The included CC BY-SA 4.0 piano MP3 and Safari page remain in `Tests/assets/` for repeatable manual testing. A user can play the file directly in Safari; importing the MP3 into Apple Music requires a separate library import/sync.

## Not verified

No human listening or acoustic measurement yet; Safari gain A/B with the listener and an active Apple Music test-track transition are pending. YouTube/Spotify/DRM, every third-party app/audio graph, headphones/Bluetooth/AirPlay/headset transitions, incoming-call/Siri recovery, physical touch/VoiceOver, full Dynamic Type, Split View/Slide Over, portrait and multi-hour endurance also remain unverified. The release is still **experimental**. See [compatibility](COMPATIBILITY.md).
