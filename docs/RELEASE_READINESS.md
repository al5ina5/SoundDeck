# Release readiness — 0.2.2 experimental

This is the honest gate report for the code published at `repos1tory/SoundDeck`, release `v0.2.2-experimental.1`, on iPad7,5 / iPadOS 17.7.8. It separates **completed**, **partially verified**, and **blocked** work.

## Gate summary

| Gate | Status | Evidence / blocker |
|---|---|---|
| Minimal dashboard and Control Center | **Complete** | Active-app rows are one app icon + slider; master is one speaker icon + slider. Light/dark captures and AX labels checked. |
| Recovery/settings access | **Complete** | Tap master speaker: Bypass/Enable, Reset volumes, Control Center add/remove, Diagnostics. Reset, bypass, diagnostics and CC add/remove exercised on-device. |
| Service stability and reactive rows | **Complete for sampled run** | Snapshots moved to a dedicated thread; only fresh audio clients get path/coalition resolution. Sampled discovery fell from ~15 s to ~49 ms; UI freshness window is 20 s. |
| Independent app gain/mute | **Verified on fixtures + Music + Safari** | RemoteIO/AudioUnit, AudioQueue, AVPlayer, AVAudioPlayer, sample-buffer, AVAudioEngine fixtures; Music 50.9→20%; Safari 80→40%; native parameter values matched. |
| Simultaneous Music + Safari | **Failed / not supported** | Starting Safari removed Music from active rows. A trial `setCategory` mix-force build did not fix it and was reverted. |
| Other real apps | **Partial / blocked** | Podcasts launched but no episode was selected. TinyDodge/RayGame launched; no audio path was detected without interaction. Photos/TV/Books/Files not exercised with non-personal media. |
| Calls/Siri/screen lock/headphones/Bluetooth/AirPlay | **Blocked** | No safe call or physical route harness in this environment; testing was paused. These are not passes. |
| Human listening / acoustic output | **Blocked** | No microphone/loopback capture or human listening; all results are PCM/native-parameter evidence. |
| Physical touch / VoiceOver / Dynamic Type / portrait | **Partial/blocked** | PSI AX labels and synthetic taps checked; no speech review, full Dynamic Type range or portrait verification. |
| Broader device/OS | **Blocked** | Only iPad7,5 / arm64 / iPadOS 17.7.8 available. No arm64e process or second iPadOS version. |
| Package/release engineering | **Complete** | Normal/tests packages, SHA256SUMS, release assets, repo transfer, website pool/index and Sileo JSON. |

## What changed in 0.2.2

- Recovery/settings sheet on the master speaker icon; no always-visible extra controls.
- Service snapshot thread and active-client-only metadata/coalition lookup; avoids the 15-second scan that made fresh rows disappear.
- UI freshness threshold widened to tolerate scheduler throttling.
- Licensed piano test asset and Safari test page (QA only).
- Research report: [optional PC-style concurrency feasibility](research/pc-style-concurrency-feasibility.md).

## Published coordinates

- Repo: `https://github.com/repos1tory/SoundDeck`
- Release: `https://github.com/repos1tory/SoundDeck/releases/tag/v0.2.2-experimental.1`
- Website: `https://repos1tory.github.io/`
- Normal package SHA-256: `4708259efd217f97b41c1d1a693974ebb47c20f9b307dcf8721aeafea0ce9cba`
- Tests package SHA-256: `ec2d4e3ab4ca41fc2763f93a97eee0da9f96862fa6a0d5e05c42b24f5766015a`

## Remaining release blockers

1. **Concurrency contract:** decide whether the product promise is per-app gain while playing (current) or requires PC-style overlap. If the latter, it is a separate opt-in research project; the report recommends against a universal interruption suppressor.
2. **Real-app matrix:** at least Podcasts, one video app, one game, one third-party player, and one protected/DRM path.
3. **Physical/route QA:** calls/Siri, screen lock, headphones, Bluetooth, AirPlay, route changes, multi-hour soak.
4. **Human/accessibility QA:** listening A/B, VoiceOver speech, physical touch, full Dynamic Type, portrait/Split View.
5. **Second device/OS** and arm64e validation.

Until these pass, the build is an **experimental prerelease**, not a broad release candidate.
