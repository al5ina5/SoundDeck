# Architecture and safety

## Audio path

The tweak is injected only into bundle identifiers in its ElleKit filter. The service derives enrolled IDs from validated preferences and checks them against installed `.app` bundles. SpringBoard and SoundDeck itself are excluded. Only the two optional fixture IDs are enabled by default. No audio daemon, SpringBoard, WebKit-wide or recording-process hook is installed.

For a direct RemoteIO playback render callback (bus 0), SoundDeck preserves the original callback and refcon in a fixed process-lifetime context, invokes it, then attenuates the returned PCM buffer **in place** before returning it to Core Audio. Gain is per process, read through a lock-free atomic float; mute is zero gain. There is no global device-volume manipulation in this path. A five-millisecond linear ramp reduces gain-step clicks. The app's own signal level is preserved multiplicatively.

PCM layouts accepted by the implementation are packed little-endian Float32, signed Int16 and signed Int32, interleaved or planar. Only mono Float32 has been measured on this device. Unknown layouts fail open. Recording buses and VoiceProcessingIO are not intercepted. AudioUnit connections that do not expose this callback are outside the implementation.

The AVPlayer adapter separately remembers requested volume per weakly tracked player object and applies an app factor to native setters. If a RemoteIO path is present, it takes priority to avoid obvious double gain. **Hybrid apps can have uncontrolled outputs; this is not a general per-process hardware mixer.** AVPlayer's real-world signal behavior is unverified.

`AVAudioSession` playback/solo-ambient activation is changed to playback + `MixWithOthers`, preserving other route options and excluding recording categories. SoundDeck does not force incoming calls, Siri or system interruptions to mix. It remembers the original category/mode/options and restores them on bypass only while the session is still playback. Subsequent recording-category changes are left alone. Complex playback-category reconfiguration after the original snapshot is not validated and can restore earlier options; bypass before such reconfiguration. An application may still stop itself when backgrounded or refuse to mix.

## Real-time constraints

- No Objective-C messaging, allocations, logging, IPC, file access or blocking locks in the render wrapper.
- Gain, format kind, ramp duration, sample counters and RMS publication use lock-free atomics.
- RMS calculation is numeric only. Audio is not recorded or retained.
- At most 128 lifetime contexts per process; disposal retires rather than frees them, avoiding callback use-after-free. Exhaustion leaves new units unchanged.
- Unit setup/reconfiguration/disposal is serialized away from render callbacks. Hosts must obey Core Audio's stop-before-reconfiguration rules.
- Main-queue heartbeat and preference callbacks do IPC and native object control. They never wait on the audio callback.

## IPC and discovery

notifyd transports compact 64-bit configuration and heartbeat state across app sandboxes. Clients never open shared preference files. Each gain namespace is keyed by the real bundle ID; each activity namespace is keyed by PID. The service enumerates live application processes, resolves their actual bundle manifests, and accepts only fresh client telemetry. It does not mistake merely running installed apps for audio producers.

The service publishes a timestamped global state once per second. Clients bypass after approximately five seconds without it. The GUI reports stale service state instead of presenting stale activity as live.

Preference writes use an advisory file lock, schema validation, per-field transactional merges and atomic replacement. GUI persistence is debounced; live slider updates use notifyd immediately. Restarted clients receive saved configuration from the service without needing the GUI to remain open.

The service caches installed-app checks until enrollment changes, bundle metadata and per-PID notify tokens. It queries freshness before reading manifests and excludes non-installation/File Provider app paths. One-second discovery/diagnostic snapshots remain a polling tradeoff in this prerelease; they have not been replaced by private system lifecycle notifications. Each dispatch callback has its own autorelease pool to prevent notification-stress memory growth.

## Master volume

The native UIKit master slider uses the device's `AVSystemController` media-volume API (`Audio/Video` category), resolved at runtime from Celestial. Availability is checked. If unavailable, the UI falls back to `MPVolumeView`. Native route selection remains `MPVolumeView`; no route is forcibly selected. Calls, ringer and recording levels are not changed. The master API was verified against `AVAudioSession.outputVolume` on this device, lowering and restoring the original level.

## Trust and privilege

The service retains real/saved root identity for one fixed operation: replacing `/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.plist`. Its effective identity is mobile for preference, process-metadata and status-file processing. Filter input is schema-validated, restricted to bundle-ID characters, checked against installed applications, and written only to a fixed root-owned path. It does not execute commands received from apps or accept arbitrary file destinations.

The app is signed as a jailbreak platform/no-container application so it can read its shared diagnostics and enumerate installed application identities. This is not an App Store sandbox model. notifyd gain messages are **not authenticated** against other local processes; this is a usability/control channel on an already-jailbroken device, not a security boundary. A hostile local process may spoof notifications or telemetry. Do not expose any of this through a network service.

Diagnostics include bundle IDs/names, PID, path type, applied gain, numeric RMS, service resource counters and timestamps. They exclude media URLs, song names, audio recordings, browser history and tokens. Opt-in `sdctl capture` captures only SoundDeck's own view hierarchy into its private directory.
