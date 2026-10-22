# Architecture and safety

## Discovery and injection

The rootless package installs an ElleKit filter for UIKit app processes, with runtime guards against system helpers, SpringBoard and SoundDeck itself. This broad filter is required for automatic discovery; there is no user enrollment allowlist. Audio code publishes a fresh per-PID telemetry token only while its supported output is active. The service resolves live app identity/metadata and groups records by bundle ID. A running app without an active supported output does not become a fake active row.

A separate WebKit filter targets WebContent and GPU subprocesses. The service resolves subprocess ownership from coalition identity and exposes it under the host app only when that mapping is unambiguous. Unknown/ambiguous owners remain uncontrollable. WebKit fixture verification on iOS 17.7.8 covered a GPU-process Web Audio PCM path and an HTML media/AVPlayer path; it does not certify all WebKit process layouts or Safari.

## Audio paths

- **RemoteIO / AudioUnit PCM:** retain original callback/refcon, invoke it, then attenuate the returned PCM in place before Core Audio consumes it. Gain is a lock-free atomic; a short ramp reduces steps/clicks. Packed Float32, Int16 and Int32 conversion is implemented; unknown formats fail open. RemoteIO plus AVAudioEngine fixture outputs were numerically measured.
- **AudioQueue:** preserves host volume and applies a per-queue factor through native queue parameters.
- **AVPlayer / AVAudioPlayer / AVSampleBufferAudioRenderer:** weakly tracks renderer/player objects, remembers host-requested base volume and writes base × per-app gain; a host volume change updates the base rather than erasing the app factor.
- **AVAudioEngine/AU providers and graph callbacks:** wraps qualifying output providers/PCM callbacks. This cannot guarantee coverage of every engine graph, remote renderer or app-specific route.
- **AVAudioSession:** playback/solo-ambient activation may be changed to playback + `MixWithOthers`, preserving route options while excluding recording, PlayAndRecord, MultiRoute and VoiceProcessingIO. Original options are restored on bypass only when the session still matches SoundDeck's applied settings. Apps may still pause themselves or change pipelines.

There is no public iOS per-process hardware-volume API. Hybrid apps can have multiple simultaneously active paths; coverage depends on which supported adapter owns the actual output. No audio is recorded, retained or inspected.

## Real-time constraints

- No Objective-C messaging, allocations, logging, IPC, file access or blocking locks in the PCM render callback.
- Gain, format kind, ramp duration and meter counters use lock-free atomics.
- RMS is numeric telemetry only; no sample content is retained.
- Fixed process-lifetime unit contexts avoid callback use-after-free; capacity exhaustion leaves new units unchanged.
- Audio object setup/reconfiguration is serialized away from render callbacks. Hosts must obey Core Audio stop-before-reconfiguration rules.
- Ordinary client notifications/heartbeat use a dispatch queue; WebKit extensions use a dedicated polling thread because their host run-loop/dispatch servicing differs.

## IPC, persistence and master volume

notifyd transports compact configuration, activity and per-process state across app sandboxes. Clients do not read the shared preference file. The service publishes timestamped global state; clients fail open to unity when backend state goes stale. Per-app preferences are validated, field-merged under a lock and atomically replaced. GUI edits publish live via notifyd and persist with a debounce.

The master slider uses the runtime-resolved `AVSystemController` media-volume API for the `Audio/Video` category, with `MPVolumeView` fallback in the dashboard. It changes system media volume, not each app's base or ringer/call/record level; route selection remains native.

## Privilege and privacy

The service retains root identity for the fixed injection-filter operation only. Preference, process metadata and status handling use mobile identity. Filter input is constrained and written to a fixed path. The app/tweak use jailbreak platform entitlements; this is not an App Store sandbox model. Local notify state is not authenticated against hostile processes on a jailbroken device.

Diagnostics include bundle IDs/names, PID, path type, gain, numeric RMS, service resource counters and timestamps. They exclude audio recordings, media URLs, song names and browser history. Opt-in captures only SoundDeck's own view hierarchy. There is no network service, analytics or cloud dependency.
