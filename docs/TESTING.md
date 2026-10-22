# Real-device validation — experimental 0.1.0

Tested directly on **iPad7,5, A10 arm64, iPadOS 17.7.8 (21H440), rootless palera1n / Procursus / ElleKit 1.2**, October 21–22, 2026. Compilation, signing, packaging, installation, launch, debugging and testing were local to this device.

## What the evidence proves

Two separate native applications generate continuous 440 Hz and 880 Hz signals through direct RemoteIO callbacks. Both deliberately request a **nonmixing** playback category; SoundDeck must provide the compatible mixing option. Each signal's peak amplitude is 0.08 to avoid loud test output.

The injected callback measures input/output PCM. Separately, each test app registers its **own Core Audio post-render observer**, which sees the buffer after the injected gain wrapper returns. These observers do not call SoundDeck's gain function. Their buffer counters and RMS independently confirm that audio is actually rendering and being changed, not merely that a requested slider value was stored.

This is **digital PCM validation before device output**, not a microphone recording, loopback capture, acoustic loudness measurement or human listening test. **No human audible result is claimed.** It does not certify an unsupported application's complete pipeline.

## Final normal-package results

[Full measured integration report](reports/integration.json) · [Package/service recovery report](reports/lifecycle.json) · [QA UIKit action/layout report](reports/ui.json)

| Test | Result |
|---|---|
| App launches / backend and actual producers discovered | Pass |
| Both signal apps render concurrently | Pass |
| A at 20%, B at 80% | **0.199892 / 0.800108 measured PCM gain** |
| Independent post-render observers | Pass, nonzero progressing buffer counters and expected RMS |
| Three additional cold launch pairs | Pass |
| A mute without changing B | Pass, A's output PCM zero; B remains at 80% |
| Unmute / independent adjustment | Pass |
| 60 rapid gain and mute cycles | Pass |
| Terminated PID disappears / app relaunch restores gain | Pass |
| Both apps backgrounded with mixer foreground | Pass |
| Mixer restart retains preferences | Pass |
| Bypass restores unity / re-enable restores mix | Pass |
| Extended background render segment | Pass, **198.8 seconds** in the final run |
| Service PID remains unchanged during integration run | Pass |
| Service-loss watchdog | Pass, independent observer returns approximately 0.05679 RMS at unity |
| Package upgrade preserves enabled state and gains | Pass |
| Actual package uninstall restores native nonmixing / unity | Pass, approximately 0.05632 RMS; first native app is interrupted by second |
| Package reinstalled and app relaunched afterward | Pass |
| Archive architecture, paths, owners, executable identity, load paths, absence of QA controls | Pass |

During the final extended segment, reported service CPU usage was **1.364% of one core** and peak RSS **5,767,168 bytes**. These are `getrusage`-based service measurements, not total system/tweak power measurements. No multi-hour endurance or battery-life claim is made.

## UI and master volume

The QA build drives **real UIKit slider and mute control actions**, checks the actual backend state, captures native light/dark landscape layouts, checks icon presence/accessibility labels, verifies at least 44pt mute controls and checks row constraints for ambiguity. These are scripted actions, **not human physical-touch or VoiceOver tests**. The normal release app excludes these QA control hooks.

The system media master slider action was exercised through the real `AVSystemController` adapter, with `AVAudioSession.outputVolume` providing an independent observation. The final QA sample started at native level 0.0625, observed a lowered output level of 0.05 and restored native level 0.0625. System output reporting is quantized/cached; the test allows 0.025 discrepancy and publishes the raw observations rather than claiming exact acoustic restoration.

Portrait automation returned the actual system error:

> The current windowing mode does not allow for programmatic changes to interface orientation.

The app declares portrait/landscape and uses scene-based adaptive constraints. No system orientation lock or unrelated setting was changed to force a passing screenshot. **Portrait remains unverified.** Public images are cropped native-window layer captures, not simulator renders; system chrome/live blur are omitted.

## Failures encountered and changes made

- Corrected compiler/linker flags and package permissions; fixed shared status-file ownership before release.
- Added explicit preferences validation, per-field locked merges, isolated malformed-input tests and 60 concurrent preference transactions.
- An earlier service build accumulated autoreleased objects during notification stress; explicit callback autorelease pools and enrollment/metadata caches replaced that behavior. An older service was observed in a per-process-limit jetsam report. The final measured run maintains one service PID and bounded reported RSS.
- Earlier discovery could stall or become stale while probing unrelated processes. Manifest reads are now limited to installed, fresh participating clients, and notify registration tokens are cached. The final extended run and watchdog/recovery tests pass. Longer-duration scheduling and system-pressure behavior remain a prerelease risk, not certified reliability.
- Initial configuration is reread at audio activation. The harness now waits for a **new fixture PID with independently observed render buffers** before switching foreground apps; FrontBoard's launch completion alone was not an audio-ready signal on this loaded older iPad.
- Corrected upgrade scripts so an enabled mixer does not remain unintentionally bypassed after upgrade.
- Normalized a rootful ElleKit dependency advertised by the local compatibility library to an explicit rootless runtime path, then validated/retested the installable normal package.
- Raw display/IOSurface capture was unavailable in this context. Used opt-in capture of SoundDeck's own real UIKit window layers instead.

## Not passed off as tested

No Safari video/WebAudio gain verification, YouTube/Spotify testing (not installed), personal Music-library playback, protected streaming, AudioQueue support, general AVAudioEngine graphs, headphones/Bluetooth/AirPlay transitions, incoming-call recovery, human listening, physical touch/animation smoothness review, all Dynamic Type sizes or multi-hour stability certification. The AVPlayer adapter is implemented but unverified. See the [compatibility matrix](COMPATIBILITY.md).

This is therefore a **limited-compatibility experimental prerelease**, not completion of a universal iPad audio mixer.
