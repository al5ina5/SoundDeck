# Compatibility matrix

| Path / feature | Status |
|---|---|
| Direct RemoteIO output callback, mono packed Float32, speaker route | **PCM-verified on iPad7,5 / 17.7.8** using two independent native apps |
| Simultaneous playback of those fixtures | **Verified**, including background playback and native nonmixing behavior after uninstall |
| Int16 / Int32 / stereo / planar RemoteIO | Implemented format handling, **not device-validated** |
| AVPlayer | Adapter implemented; **real-media gain not verified** |
| AVAudioPlayer / AudioQueue | **No adapter**; do not assume support from incidental internal RemoteIO use |
| AVAudioEngine connection-based graphs | **Not supported generally**; only a callback meeting the documented RemoteIO conditions can be affected |
| Apps using multiple different audio pipelines | **Not guaranteed**; some outputs can bypass the selected path |
| Safari video / WebAudio / WebKit subprocesses | **Unsupported attribution/control** in this release; enrolling Safari alone does not inject its separately sandboxed media processes |
| YouTube / Spotify | **Not installed on the test device; not tested** |
| Music / protected streaming / DRM | **Not tested**; no personal library playback used |
| Phone calls / recording / VoiceProcessingIO | **Intentionally excluded** |
| Siri, incoming-call interruption and automatic recovery | Native system behavior retained; **not validated** |
| Bluetooth / headphones / AirPlay / route transitions | Native route handling retained; **not physically validated** |
| Master media volume on current speaker route | Native API plus UIKit action checked against actual system volume |
| Light/dark landscape layout | Captured and inspected on-device |
| Portrait | Declared/adaptive layout; **not verified**: system refused programmatic orientation in the current windowing mode |
| Split View / Slide Over | Scene-based UIKit support implemented; **not interactively tested** |
| VoiceOver / full Dynamic Type size range | Labels, scaled fonts, 44pt mute controls implemented; **human accessibility review pending** |
| Ducking | **Not implemented**, no nonfunctional switch is shown |
| Jailbreak inactive | No injection, therefore stock audio. The `/var/jb` application may be unavailable until re-jailbreaking |

## Why there is no universal claim

iOS has no public Windows-style per-process hardware-volume API. Applying one global volume setter to every app cannot satisfy independence. SoundDeck instead attenuates a specific app's actual callback buffers. A framework that renders remotely, uses an unwrapped graph connection, or stops itself on backgrounding cannot be made supported merely by giving it a slider.

The app discovers **participating audio producers**, not every possible system audio session. Unsupported paths can remain in Saved Applications but will not acquire fabricated activity or meters. Adding a bundle to the filter is opt-in injection, not proof of support.

## Conflicts reviewed

The inspected device uses ElleKit 1.2 and has no installed VolumeMixer audio hooks. The injection directory contains unrelated display, battery, launcher and system-utility tweaks; none were disabled or modified. Xios/PulseAudio components are installed for its separate desktop environment; interoperability with those audio routes is untested. Other mixers/audio-session tweaks could multiply gain or fight session options; do not combine them without a controlled test.
