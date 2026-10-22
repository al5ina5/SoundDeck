# SoundDeck

**Experimental native iPad audio mixer for rootless jailbreaks.** Real per-process gain, not sliders wired to the system's single volume setting.

> This is a limited-compatibility prerelease, not a universal Windows mixer. Independent PCM gain is verified with two on-device RemoteIO test applications. Safari/WebKit, DRM playback and arbitrary App Store applications are **not** verified or universally supported. See [compatibility](docs/COMPATIBILITY.md) and [device test evidence](docs/TESTING.md).

<img src="docs/images/landscape-light.png" width="720" alt="SoundDeck native iPad dashboard in light appearance">

<details><summary>Dark appearance</summary>
<img src="docs/images/landscape-dark.png" width="720" alt="SoundDeck native iPad dashboard in dark appearance">
</details>

Screenshots are cropped captures of the actual on-device UIKit view hierarchy, not mockups. Layer capture omits system chrome and live blur effects; saved application rows are excluded from public images.

## What works

- Separate 0–100% app gain and mute for supported direct RemoteIO playback callbacks.
- Concurrent playback through opt-in `MixWithOthers` handling for playback sessions.
- Persistent, bundle-ID-keyed preferences and remembered applications.
- Real application icons, playback activity, current output name, light/dark appearance, native accessibility labels, Dynamic Type fonts and iPad scene-based layouts.
- System media master volume, independently of app gain; route selection remains the native system control.
- A five-second backend-loss watchdog, bypass, reset, diagnostics and scoped emergency recovery.
- An experimental per-object AVPlayer adapter. **Its real-media behavior is not validated and is not part of the verified compatibility claim.**

Verified environment: **iPad 6th generation / iPad7,5 / A10 arm64 / iPadOS 17.7.8 (21H440) / palera1n rootless / Procursus / ElleKit 1.2**. This build is arm64-only. Other devices and OS versions require validation; arm64e system processes need a suitable rebuild.

## Install

Install the `.deb` from the GitHub prerelease using Sileo/Zebra, or:

```sh
sudo dpkg -i com.alsinas.sounddeck_0.1.0_iphoneos-arm64.deb
```

Open SoundDeck, tap **+**, enroll an application, then restart **that application** to load the tweak. Enrollment is not a compatibility guarantee. No SpringBoard/audio-daemon injection or respring is required. Recording, calls and VoiceProcessingIO are intentionally excluded.

Optional verification signals are in `com.alsinas.sounddeck.tests_0.1.0_iphoneos-arm64.deb`. These are quiet, continuous 440/880 Hz generators, not fake application entries. They run only when explicitly launched. Stop them when finished testing.

## Build locally

Dependencies: a jailbroken arm64 device, Clang/Clang++, iOS SDK, Foundation/UIKit framework stubs, make, Python 3, ldid, dpkg-deb, ElleKit's substrate compatibility library, and uikittools. Everything was compiled, signed, packaged and installed **on this iPad**, without an external runner.

```sh
git clone https://github.com/al5ina5/SoundDeck.git
cd SoundDeck
export SDK=/var/jb/usr/share/SDKs/iPhoneOS.sdk
bash build.sh
sudo dpkg -i packages/com.alsinas.sounddeck_0.1.0_iphoneos-arm64.deb
```

The SDK is not included. The build defaults to deployment target iOS 15, arm64, and `/var/jb` package paths. Exact build prerequisites and the QA workflow are in [BUILDING.md](docs/BUILDING.md). Building with `--tests` additionally creates a QA app package and the separate signal-fixture package. **The normal package has no scripted UI-test hooks.**

## Recovery and removal

```sh
sdctl disable                    # unity gain; restore requested session options
sudo apt remove com.alsinas.sounddeck.tests com.alsinas.sounddeck
```

If an enrolled app crashes before it can receive bypass, rename `/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.plist` to `SoundDeck.plist.disabled`, stop `com.alsinas.sounddeck`, then restart only the affected app. The service regenerates the filter while running, so stop it as well. [Full recovery instructions](docs/TROUBLESHOOTING.md).

Uninstall retains SoundDeck preferences intentionally and restores native behavior for new app processes. Already-running apps retain mapped tweak code until restarted, but bypass/watchdog restores unity gain. When the jailbreak is inactive, injection is absent and audio is stock; the rootless application itself may not be launchable until the jailbreak returns.

## Architecture

| Module | Purpose |
|---|---|
| `App/` | UIKit dashboard and native master-media-volume adapter |
| `Backend/Tweak.mm` | Allowlisted process-local RemoteIO / AVPlayer / playback-session hooks |
| `Backend/Service.m` | Preferences publication, discovery and diagnostics |
| `Shared/` | notifyd protocol, validation, locked transactional persistence |
| `Tests/` | Unit, device PCM, UI-action and package-recovery tests |
| `Packaging/` | Rootless Debian metadata and reversible lifecycle scripts |

There is no audio recording, network service, analytics, cloud dependency or content inspection. IPC and diagnostics contain gains, bundle identifiers, playback activity and numeric RMS. Root privilege is used only to maintain a fixed, validated injection-filter file; user-file processing runs with mobile's effective identity. See [architecture and security](docs/ARCHITECTURE.md).

## Current limitations

No AudioQueue adapter, general AVAudioEngine graph support, WebKit subprocess attribution, automatic ducking, multi-hour endurance certification, verified Bluetooth/AirPlay/headphone transitions, or human listening confirmation. Portrait is declared and uses adaptive UIKit constraints, but programmatic portrait verification was blocked by this iPad's current windowing mode. Do not treat untested paths as supported.

MIT licensed. [Third-party notices and research attribution](THIRD_PARTY_NOTICES.md).
