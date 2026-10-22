# Compatibility matrix — 0.2.0 experimental

All device measurements below were made on **iPad7,5 / A10 arm64 / iPadOS 17.7.8 (21H440) / rootless palera1n / ElleKit 1.2** with SoundDeck's separate QA fixtures. They establish that an adapter changed its real PCM buffer or native per-object volume parameter; they do not establish human-perceived loudness, arbitrary app compatibility, or route-wide output behavior.

| Path / feature | Status on test device |
|---|---|
| RemoteIO / AudioUnit output PCM | **PCM-verified**: simultaneous mono Float32 fixtures at independent 20% / 80%, mute isolation, bypass and independent post-render observations. Packed Float32, Int16, Int32 and planar conversion are implemented; only Float32 fixture format measured. |
| AudioQueue | **Native adapter verified**: `AudioQueueSetParameter` volume tracked 0.9 × 0.4 = 0.36, host base change 0.6 × 0.4 = 0.24, mute = 0. |
| AVPlayer | **Native adapter verified** on local fixture: 0.9 × 0.4 = 0.36, host base change and mute. No commercial/DRM media app tested. |
| AVAudioPlayer | **Native adapter verified** on local fixture: 0.9 × 0.4 = 0.36, host base change and mute. |
| AVSampleBufferAudioRenderer | **Native adapter verified** on local fixture: 0.9 × 0.3 = 0.27, host base change and mute. |
| AVAudioEngine | **PCM-verified on fixture**: output/input RMS ratio 0.6; separate post-render observer agreed within measurement tolerance. Not every engine graph/output provider is covered. |
| WebKit Web Audio | **Fixture verified**: GPU subprocess coalition attribution resolved to the host app; PCM ratio 0.349947 at 35%, mute produced zero output. |
| WebKit HTML media | **Fixture verified**: GPU subprocess attributed to host app; AVPlayer volume was 0.35 at 35%, mute set it to zero. |
| Simultaneous playback | Five non-WebKit fixture adapters ran at distinct gains in separate processes. The pair of RemoteIO signal fixtures also ran concurrently/backgrounded. |
| Safari, YouTube, Spotify, commercial browsers | **Not tested**. The WebKit fixture does not certify Safari or every WebKit subprocess/audio route. YouTube and Spotify were not installed. |
| Protected streaming / DRM / personal Music library | **Not tested**; no personal media used. |
| Arbitrary third-party apps / apps with hybrid pipelines | **Not guaranteed**. An app may use unsupported paths, multiple renderers, remote audio or stop playback on its own. No manual enrollment can make such a path supported. |
| Recording, calls, PlayAndRecord, MultiRoute, VoiceProcessingIO | **Intentionally excluded** to avoid altering capture/call paths. |
| Master media volume | Native `AVSystemController` setter/getter exercised and restored; system-volume observations are quantized/cached. Route selection remains native. |
| Headphones, Bluetooth, AirPlay, route transitions, incoming calls/Siri | Native system routing/interruption behavior is retained, but physical transition/recovery tests remain **unverified**. |
| Dashboard and Control Center | Light/dark landscape captures and scripted UIKit/Control Center control actions passed. Physical touch, VoiceOver and full Dynamic Type review remain **pending**. |
| Portrait, Split View, Slide Over | Adaptive scene/layout code exists; portrait automation was blocked by iPadOS windowing policy. Multitasking layouts are **not interactively tested**. |
| Ducking | **Not implemented**. |

## Discovery and controllability

The tweak is injected broadly into UIKit app processes for automatic discovery, then applies runtime guards. It also injects a dedicated agent into WebKit WebContent/GPU processes. The service publishes a per-app row only from fresh audio telemetry and groups a WebKit process to its host only when coalition ownership is unambiguous. An ambiguous or excluded path is bypassed/marked uncontrollable, not represented by a fake active slider. Saved gains are keyed by bundle ID and survive process/app restarts.

## Why compatibility is limited

iOS has no public Windows-style per-process hardware volume API. SoundDeck therefore combines supported PCM attenuation with native framework volume adapters. A successful launch, active player clock, or requested preference alone is not proof of an audible effect. Tests report either PCM ratios/observers or the framework volume property they actually measured; they do not claim acoustic measurements. Other devices, OS builds and apps need verification before their paths should be considered supported.

## Environment and conflicts

The inspected device runs ElleKit 1.2 and has no installed VolumeMixer audio hooks. Unrelated installed tweaks were not disabled or modified. Other audio/session mixers may compete over gain or session options; do not combine them without controlled testing. The package is rootless and arm64-only; arm64e/system-process support requires a suitable rebuild and validation.
