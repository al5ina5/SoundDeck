# PC-style concurrent audio on rootless iPadOS: feasibility report

**Status:** research only. This report is the only file authored for this research. No shipping source, packaging, preference, media, or user playback was changed by this research.

**Device under study:** iPad7,5 (iPad 6th generation), A10 arm64, iPadOS 17.7.8 (21H440), rootless palera1n, Procursus, ElleKit 1.2.

**Scope:** iPadOS 15–18, rootless jailbreak. The report distinguishes what is publicly documented, what is visible in source, and what is inferred. It does **not** claim any audio was heard, recorded, or measured acoustically. The existing Music/Safari failure is quoted from the project's own test notes; it was not reproduced for this report.

**Evidence legend**

| Tag | Meaning |
|---|---|
| `[V]` | Verified from a primary source: Apple SDK header/documentation, WebKit source, the SoundDeck repository, or read-only inspection of this device. |
| `[I]` | Inferred: a conclusion drawn from `[V]` facts, but not directly observed on this device/build. |
| `[U]` | Unknown/unverified: needs an experiment, a different build, or private-API inspection. |

---

## Executive summary

**Verdict: feasible only as a best-effort, app-specific, opt-in compatibility mode — not as a universal PC-style guarantee.**

- At the public-API level, iOS exposes one supported family of levers for "do not interrupt the other app": make the **starting** session mixable with `AVAudioSessionCategoryOptionMixWithOthers` (or an option that implies it), and do it **before activation**. `[V]`
- That lever works for ordinary output-only `Playback` sessions: SoundDeck's own non-mixing fixture apps become concurrent when the existing `setActive` hook applies the option. `[V]` (repository tests)
- It did **not** make Music + Safari coexist on this device. `[V]` (project-reported). That failure is not proof that mixing cannot work; it is consistent with several concrete implementation and platform causes, including a first-activation timing race in SoundDeck, WebKit's four-argument `setCategory` path, WebKit's `PlayAndRecord` capture path, long-form-audio policy, and app-level Now Playing/self-pause behavior. `[I]`/`[U]`
- A universal mode that survives calls, Siri, recording, alarms, DRM, WebKit, system apps, and route changes would require interfering with `mediaserverd`/`AudioSessionServer` or suppressing system interruptions. That is private, version-fragile, and carries unacceptable call/emergency/boot-loop risk. **Do not implement that.** `[I]`
- **Recommendation for 0.2.x: do not add a universal concurrency feature.** If product wants to explore it, build a hidden 0.3 spike around the **narrowest** design: a per-app "this app may start without stopping others" allowlist that only forces mixability on output-only `Playback` sessions, never on `Record`/`PlayAndRecord`/`MultiRoute`/voice, with a 10-minute auto-expiry and a kill switch. Timebox it and abandon it if Music + Safari still fails with diagnostics showing Safari was genuinely mixable at activation. `[I]`

**Confidence:** high that `MixWithOthers`/`DuckOthers`-style options are the only public mechanism; high that universal suppression is not safely achievable with public APIs; medium that a per-app mode can work for some ordinary apps; low that Music + Safari can be made reliable without a WebKit-specific or private-layer intervention.

---

## 1. Exactly how iOS decides to interrupt or pause a session

### 1.1 The session model

Every app process that uses AVFoundation/AudioToolbox has an `AVAudioSession` singleton. The session carries:

- a **category** (`Playback`, `PlayAndRecord`, `Record`, `Ambient`, `SoloAmbient`, `MultiRoute`, …),
- a **mode** (`Default`, `MoviePlayback`, `SpokenAudio`, `VoiceChat`, `VideoChat`, …),
- **category options** (`MixWithOthers`, `DuckOthers`, `InterruptSpokenAudioAndMixWithOthers`, Bluetooth/AirPlay options, …),
- a route-sharing policy (`Default`, `LongFormAudio`, `LongFormVideo`, `Independent`), and
- an **active/inactive** state.

The category is the app's declaration of intent. The system is the arbiter; the app cannot name a numeric priority or force another app to keep running. Apple's archived guide describes the system as a control tower and says the app "can make audio requests and state its desired priority, but final authority ... comes from the system." `[V]` ([Activating an Audio Session](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/ConfiguringanAudioSession/ConfiguringanAudioSession.html))

### 1.2 The interruption contract

Apple's definition is unusually direct:

> "An *audio interruption* is the deactivation of your app's audio session—which immediately stops your audio. Interruptions happen when a competing audio session from an app is activated and that session is not categorized by the system to mix with yours." `[V]`
> — [Responding to Interruptions](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html)

The same guide gives the sequence: the starting app requests activation; the system considers its category; the system **deactivates the Music app's session**, stopping playback; then it activates the new session. `[V]`

Two consequences matter for any design:

1. The stop happens at the **session/server layer**, before or around the notification. The `AVAudioSessionInterruptionNotification` is a report that the session was deactivated, not a veto the app can use to prevent it. `[V]`
2. AVFoundation playback (`AVPlayer`, `AVAudioPlayer`, `AVAudioEngine` in the common case) automatically pauses on interruption. AudioQueue and raw RemoteIO leave more of the reaction to the app. Suppressing the notification in one app does not automatically restart its player or re-activate its session. `[V]`/`[I]`

**Version note:** newer AVFAudio SDKs describe `AVAudioSessionDidBecomeInactiveNotification` and `AVAudioSessionResumptionRecommendationNotification` and deprecate `interruptionNotification` in newer OS releases. The iPadOS 17.7.8 SDK header inspected here does not expose those newer symbols. Any hook must feature-detect selectors/notifications and must not assume one interruption model across 15–18 and later releases. `[V]` (Apple docs + local header); `[I]` (design implication)

### 1.3 Mixability is a property of the *starter*, evaluated at activation

The SDK header is precise:

> "Controls whether other active audio apps will be interrupted or mixed with when your app's audio session goes active." `[V]`
> — `AVAudioSessionTypes.h`, `AVAudioSessionCategoryOptionMixWithOthers`

And Apple's current documentation:

> "Clearing this option and then activating your session interrupts other audio sessions. If you set this option, your app mixes its audio with audio playing in background apps, such as the Music app." `[V]`
> — [mixWithOthers](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers)

Important constraints:

- `MixWithOthers` is valid only with `PlayAndRecord`, `Playback`, and `MultiRoute`. `Ambient` gets it automatically; `SoloAmbient` and `Record` cannot set it. `[V]` (SDK header; Apple docs)
- `DuckOthers` and `InterruptSpokenAudioAndMixWithOthers` also imply `MixWithOthers`. `DuckOthers` lowers other apps rather than stopping them; `InterruptSpokenAudioAndMixWithOthers` stops only sessions whose mode is `SpokenAudio` (podcasts, spoken audio) and mixes with everything else. `[V]` (SDK header)
- Options are **not sticky across category changes**. An app that changes category must reassert them. `[V]` (SDK header)
- The decision is made when the session **goes active**, not retroactively when options change on an already-active session. The react-native-video maintainers documented this after observing that activating with `.mixWithOthers` and only later removing it leaves the other app playing, because iOS decided at activation. `[V]` ([issue #5140](https://github.com/TheWidlarzGroup/react-native-video/issues/5140))
- Changing the category while active causes an immediate route change and can reconfigure the audio system. It is generally preferable to configure before activation. `[V]` ([setCategory](<https://developer.apple.com/documentation/avfaudio/avaudiosession/setcategory(_:mode:options:)>); archived guide)

So the first question in any failure is not "did the app handle the interruption?" but **"was the starting app's session actually mixable at the instant it called `setActive:YES`?"** `[I]`

### 1.4 What "session priority" means publicly

There is no public, numeric, per-app priority API. `[V]` What exists publicly is a set of category and option semantics:

| Category | Silenced by Ring/Silent and lock? | Interrupts non-mixable apps? | Input? |
|---|---|---|---|
| `Ambient` | Yes | **No** | Output only |
| `SoloAmbient` (default) | Yes | **Yes** | Output only |
| `Playback` | No | **Yes by default; no with mix override** | Output only |
| `Record` | No | **Yes** | Input only |
| `PlayAndRecord` | No | **Yes by default; no with mix override** | Input + output |
| `MultiRoute` | No | **Yes** | Input + output |

Source: Apple's archived [Audio Session Categories and Modes](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioSessionCategoriesandModes/AudioSessionCategoriesandModes.html), Table B-1. `[V]`

Other priority-like facts:

- During a phone call, an app may activate a `Playback` session (for SharePlay, for example), but `Record`/`PlayAndRecord` activation can fail with `AVAudioSessionErrorCodeInsufficientPriority` because it would capture the call microphone. `[V]` (SDK header, `setActive:withOptions:error:`)
- `AVAudioSession.setPrefersNoInterruptionsFromSystemAlerts(_:)` (iOS 14.5+) lets a session prefer not to be interrupted by ringtones/alerts and banner-style incoming calls. It does **not** cover app-vs-app playback arbitration, and a full-screen call still interrupts. It is a call/alert behavior knob, not a mixing mechanism. `[V]` (SDK header)
- `InterruptSpokenAudioAndMixWithOthers` is the only public "interrupt only this class of app" behavior. It is not a general PC-style mixer. `[V]`

The exact ordering and tie-breaking inside `mediaserverd`/`AudioSessionServer` are not public. Any claim of a numeric "session priority" should be treated as implementation folklore, not API. `[V]`/`[I]`

### 1.5 Foreground, background, suspension

- Background audio requires the `audio` background mode plus an appropriate category. Without it, an app can be suspended and its session torn down. `[V]` (archived guide)
- Apple notes that a **non-mixable** session should be deactivated when the app goes to the background and is not actively using audio; otherwise the system may deactivate it and the app receives a "somewhat confusing" interruption notification. `[V]` ([interruptionNotification](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification))
- A foreground app with a non-mixable session can interrupt background audio. A mixable starter is supposed to mix with background apps such as Music. `[V]` (docs quote above)
- WebKit additionally restricts background playback: video in background tabs is restricted, and `VideoAudio` has `ConcurrentPlaybackNotPermitted`, `BackgroundProcessPlaybackRestricted`, and `SuspendedUnderLockPlaybackRestricted` restrictions. `[V]` (`MediaSessionManagerIOS.mm`, WebKit main)

This matters because "Safari is in the foreground" is not the same as "Safari's audio session is a foreground app session"; WebKit's media session runs in an auxiliary process with its own restrictions. `[V]`/`[I]`

### 1.6 WebKit's media stack (the Safari-specific part)

WebKit does not simply call `AVAudioSession` from the Safari UI process. The relevant code is in `Source/WebCore/platform/audio/` and runs in the WebKit GPU process for media playback on modern iOS. `[V]` (WebKit source; `AudioSessionCocoa::tryToSetActiveInternal` requires a presented host PID when called from an auxiliary process, and explicitly dispatches activation)

The verified behavior in WebKit main (October 2026) is:

1. **Category selection** in `MediaSessionManagerCocoa::updateSessionState()`:
   - `PlayAndRecord` + `VideoChat` when there are active capture sources, or when audio is playing and the session is already `PlayAndRecord`.
   - `Playback` (`MediaPlayback`) for audible audio or video.
   - `Ambient` for Web Audio-only output.
   - `None`/`Ambient` after a delay when nothing is audible.
   `[V]` ([MediaSessionManagerCocoa.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/cocoa/MediaSessionManagerCocoa.mm))

2. **Four-argument category setter**: `AudioSessionIOS::setCategory` calls
   `[session setCategory:categoryString mode:modeString routeSharingPolicy:... options:options error:&error]`
   with `options = 0` for ordinary media playback. It does **not** include `MixWithOthers`, and it is not the three-argument selector SoundDeck currently swizzles. `[V]` ([AudioSessionIOS.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/ios/AudioSessionIOS.mm))

3. **Long-form audio policy**: for `MediaPlayback`, WebKit uses `RouteSharingPolicy::LongFormAudio`; when the `AVSYSTEMROUTING_FRAMEWORK` path is compiled in, the policy is `LongFormAudio` more broadly. This is the policy used by music/podcast-style long-form audio. `[V]` (same file)

4. **Activation**: `AudioSessionCocoa::tryToSetActiveInternal(true)` calls
   `[[AVAudioSession sharedInstance] setActive:YES withOptions:0 error:&error]`
   synchronously on a serial "AudioSession Activation Queue". `[V]` ([AudioSessionCocoa.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/cocoa/AudioSessionCocoa.mm))

5. **Interruption observer**: `AudioSessionIOS` registers for `AVAudioSessionInterruptionNotification`; on `.began` it calls `beginInterruption()`, and WebKit pauses its media sessions. It also observes route changes and can pause on `OldDeviceUnavailable`. `[V]` (WebKit source)

6. **Now Playing / MediaRemote**: WebKit calls `MRMediaRemoteSetCanBeNowPlayingApplication(true)`, sets now-playing info, and registers remote commands; `MediaSessionHelperIOS` calls `beginReceivingRemoteControlEvents` and attributes the session to the host app PID via `AVSystemController_PIDToInheritApplicationStateFrom`. `[V]` (WebKit source)

7. **Host attribution**: WebKit uses `setHostProcessAttribution:` and `setAuditTokensForProcessAssertion:` so the auxiliary process's audio can be attributed to Safari. `[V]` (WebKit source)

Session ownership is **process-local**: Safari's UI process does not own the `AVAudioSession` that plays the page; the GPU process does, with host attribution. A hook installed only in `Safari.app` would not change the audio session that actually plays. `[V]`/`[I]`

This explains both why SoundDeck can control Safari's AVPlayer gain (the GPU process is injected and attributed) and why a session-level fix must reach the **GPU process's** four-argument `setCategory` and `setActive` path, not just Safari's UI process. `[V]`/`[I]`

### 1.7 Music, AVPlayer, and MediaRemote

Music is a system media app; its playback stack is generally AVFoundation/MediaPlayer, but this was not directly inspected here. Its exact session configuration is not public and cannot be read from another process without private APIs. `[I]`/`[U]` What is known:

- It is a primary, non-mixable playback app in normal use; it is the app users expect to be "Now Playing." `[I]`
- `AVPlayer`/AVFoundation automatically pause on interruption. `[V]` (archived guide)
- WebKit and Music both publish now-playing state through MediaRemote; only one app is normally the Now Playing app. `[V]` (WebKit source; WWDC22). MediaRemote now-playing state is a separate arbitration/UI layer from the audio session's active/interrupted state; a now-playing change alone does not prove the audio session was deactivated. `[I]`
- Apple's WWDC22 session states that Now Playing eligibility requires a remote-command handler and a **non-mixable** category/option; mixable sessions are "generally used when playing back notifications" and are not good Now Playing candidates. `[V]` ([WWDC22 session 110338](https://developer.apple.com/videos/play/wwdc2022/110338/), ~3:30–4:05)
- Whether Music *pauses* merely because it loses Now Playing is app-specific and not documented. It is a plausible additional cause, not a proven one. `[U]`

### 1.8 One-line model

> The starter asks the server to activate. The server compares the starter's category/options/mode and the victim's state. If the starter is not mixable and the victim is a normal primary session, the server deactivates the victim; the victim's AVFoundation player pauses; then the server posts an interruption notification. Making the starter mixable **before** activation is the only public way to avoid that chain. `[V]` for the documented steps; `[I]` for the exact internal ordering.

---

## 2. Is `MixWithOthers` sufficient? Why the Safari/Music case still stopped Music

### 2.1 What the public contract predicts

If Safari's session is `Playback` + `MixWithOthers` at the moment it calls `setActive:YES`, the documented behavior is that Music, a background app, is **not** interrupted and both mix. `[V]` (Apple docs quote in §1.3)

If Safari's session is `Playback` with no mix option, or `SoloAmbient`, or `PlayAndRecord` without mix, the documented behavior is that non-mixable apps are interrupted. `[V]` (Table B-1)

Therefore the observed failure means at least one of these was true at activation:

- Safari's session was not actually mixable;
- Safari was mixable but the system applied a different arbitration rule (long-form policy, now-playing, call/voice priority);
- Music was stopped by its own app logic or by MediaRemote rather than by session deactivation; or
- the implementation did not reach the right process/selector/timing.

### 2.2 The observed case (project-reported, not reproduced here)

The repository's 0.2.1 notes record:

- A non-personal Apple Music station was playing.
- The stock CC BY-SA piano MP3 was started in Safari.
- Music left the active service rows; Music's AVPlayer stopped.
- A trial build that forced `MixWithOthers` through `AVAudioSession` category hooks did not make both continue; it was reverted before packaging.

Sources: `RELEASE_NOTES.md`, `docs/TESTING.md`, `docs/COMPATIBILITY.md`. `[V]` as project records; the underlying event is `[U]` for this report because it was not rerun.

### 2.3 The shipped 0.2.1 path is weaker than "category mixing" sounds

This is the most important code-level finding. The released 0.2.1 runtime already contains a best-effort mix path, and it is **on by default**:

- `Backend/Runtime.mm:12` initializes `mixing{true}`.
- `Shared/SDPreferences.m:7` defaults `mixing` to `@YES`.
- `Shared/SDProtocol.h:27` maps the preference to global state bit 12.
- `Backend/Runtime.mm:210-213` hooks `-[AVAudioSession setActive:withOptions:error:]` and calls `applyMix(self)` before the original activation when `enabled && mixing`.
- `Backend/Runtime.mm:199-204` `applyMix` only handles `Playback` and `SoloAmbient`; it changes `SoloAmbient` to `Playback` and ORs in `MixWithOthers`, clearing `DuckOthers`.
- There is **no** `setCategory` hook in 0.2.1. `Backend/Runtime.mm:251` hooks only `setActive:withOptions:error:`.
- `Backend/Runtime.mm:198` excludes `Record`, `PlayAndRecord`, and `MultiRoute` from `allowed()`.
- WebKit agent processes do not use notify watchers; they poll `update()` every 500 ms in `webHeartbeat` (`Backend/Runtime.mm:188-191`), and `enabled` starts `false` (`:12`).

Consequences:

1. **It changes silent-switch behavior.** For an app using `SoloAmbient`, `applyMix` changes the category to `Playback` to make `MixWithOthers` legal. `Playback` is *not* silenced by the Ring/Silent switch; `SoloAmbient` is. That is a real behavioral regression for games/UI-sound apps, independent of concurrency. `[V]` (code + Table B-1)
2. **It is global, not per-app.** Any injected app with a `Playback`/`SoloAmbient` session gets the treatment while the global `mixing` bit is on. `[V]`
3. **It cannot fix a first activation that happened before `enabled` became true.** `setActive` checks `enabled.load()`; if the WebKit GPU process calls activation during its first 0–500 ms, the hook skips `applyMix`, the original activation proceeds non-mixably, and Music is deactivated. A later `update()` may call `applyMix` on the now-active session (`:219`), but changing options after activation does **not** retroactively undo the interruption. `[V]` for the code path; `[I]` for this being the observed failure.
4. **It is easy for WebKit to overwrite.** WebKit calls the four-argument `setCategory` on every `updateSessionState()` with `options = 0`. SoundDeck does not intercept that selector. Even if `applyMix` wins at activation, a subsequent WebKit category update can clear `MixWithOthers`; options are not sticky. `[V]` (WebKit source + SDK header)
5. **It does not restore on category changes.** `restoreMix` runs only when the global mode is turned off (`:220`), not when the app changes category or deactivates. The app's own category change may clear the options anyway; the bookkeeping then no longer matches. `[V]`
6. **It may glitch audio.** Calling `setCategory` synchronously inside the `setActive` hook, while the session is being activated on WebKit's serial activation queue, can trigger an immediate route reconfiguration. It may work, but it is not free. `[V]` (Apple docs on changing category while active) `[I]` for the glitch severity.

The unpublished branch that also hooked `setCategory` is **not in this repository's history**. `git log --all` shows only the published commits, and `git fsck --lost-found` reported no dangling commits. `[V]` (repository inspection). Its exact selectors, process coverage, gating, and ordering cannot be audited from here. Do not treat that failure as proof that a correct four-argument `setCategory` hook cannot work. `[I]`

### 2.4 Candidate causes, ranked

| # | Hypothesis | Evidence | Status | How to discriminate |
|---|---|---|---|---|
| 1 | **First-activation race**: WebKit GPU process activates before `enabled` is true (0–500 ms poll), so `applyMix` is skipped; Music is interrupted before the later `applyMix`. | `Runtime.mm:12`, `:188-191`, `:210-213`, `:214-220`; WebKit activates in an auxiliary process on a serial queue. | `[I]` high likelihood | Log `enabled`, `mixing`, hook hit, category/options at every `setActive`; pre-warm mode before Safari play; retry a second play after the GPU process is warm. If second play mixes, race is confirmed. |
| 2 | **Four-argument `setCategory` not hooked**; WebKit reasserts `options=0` after activation, clearing mixability. | WebKit `AudioSessionIOS.mm`; SDK: options not sticky; 0.2.1 has no `setCategory` hook. | `[I]` high likelihood | Hook both `setCategory:mode:options:error:` and `setCategory:mode:routeSharingPolicy:options:error:`; log options before/after each WebKit update. |
| 3 | **WebKit `PlayAndRecord`/capture path** is excluded by `allowed()`, so Safari never becomes mixable. | WebKit sets `PlayAndRecord` when `captureCount > 0` or when already `PlayAndRecord` and playing; `Runtime.mm:198` excludes it. | `[I]` medium | Log Safari's actual category/mode during playback; test a page with and without `getUserMedia`; test a fresh Safari process with no prior capture. |
| 4 | **Long-form audio policy conflict**: WebKit uses `LongFormAudio` for `Playback`; Music is also long-form; the server may arbitrate two long-form clients differently from ordinary mixable sessions. | WebKit source uses `RouteSharingPolicy::LongFormAudio`; Apple does not document two-long-form-client behavior. | `[U]` | Compare Web Audio-only (Ambient) vs `<audio>` (Playback/LongForm) against Music; if Ambient mixes and `<audio>` does not, this is a strong signal. |
| 5 | **Music self-pauses / loses Now Playing** rather than being deactivated. | WebKit claims Now Playing via MediaRemote; WWDC22 says mixable sessions are not Now Playing candidates; no public doc says loss of Now Playing pauses Music. | `[U]` | In Music, log `AVAudioSessionInterruptionNotification` and `isActive`; if no interruption and session stays active while `AVPlayer.rate` goes 0, it is app/Now-Playing logic. |
| 6 | **Stale app process**: Music or Safari was running before the tweak was installed/updated, so it never loaded the hook. | README instructs restarting apps after install; system apps can be long-lived. | `[U]` operational | Kill/relaunch Music and Safari before the test; compare. |
| 7 | **Mode off/stale service**: `mixing` bit is 0, service state stale, or `disabled` is set. | `Runtime.mm:174`, `:216`, `SDGlobalFresh`; prefs default is on. | `[V]` code path; `[U]` instance | Check `sdctl status` and global state before the test; assert bit 12 is set; log freshness. |
| 8 | **Music is interrupted by a later non-mixable event**, not by Safari's activation (e.g., a notification sound, Now Playing transition, route change). | Interruptions can come from many sources. | `[U]` | Correlate timestamps of interruption, route change, and Safari activation. |

### 2.5 Why suppressing the interruption notification alone cannot fix it

A tempting shortcut is to swizzle `NSNotificationCenter` or `AVAudioSession` so the victim never sees `AVAudioSessionInterruptionNotification`. That is not sufficient:

- The server has already deactivated the victim's session; audio has stopped. `[V]` (Apple definition)
- AVFoundation's own interruption handling pauses the player internally; hiding the public notification does not necessarily stop that internal pause, and it definitely does not re-activate the session. `[V]`/`[I]`
- An app that ignores the interruption but keeps its UI in "playing" state will show a lie: the player is stopped, the session is inactive, and the user sees a play button that does nothing. `[V]` (logical consequence)
- If the app is suspended, it may not run your resume code at all. `[V]` (archived guide)
- Suppressing notifications globally would also hide **call/Siri/alarm** interruptions from apps, which is unsafe and confusing. `[V]` (design consequence)

The only safe notification-layer use is **observation and diagnostics**, not suppression. `[I]`

### 2.6 What the failure does and does not prove

It proves that "add `MixWithOthers` somewhere in `setActive`" is not a complete solution on this device/build. `[V]`
It does **not** prove that a per-app, correctly timed, four-argument `setCategory` + `setActive` intervention cannot make a specific pair of ordinary apps mix, because the shipped code has the race and coverage gaps above. `[I]`

---

## 3. Possible intervention layers

The table is ordered from least to most invasive. "Scope" means which processes/apps are affected.

| Layer | Mechanism | Scope | Likely side effects | Entitlements / privilege | iOS fragility | Reversibility | Verdict |
|---|---|---|---|---|---|---|---|
| **L0. Per-app gain/limiter (existing)** | PCM attenuation or framework-native volume; no session arbitration. | Selected apps. | None for concurrency; does not stop interruptions. | Normal injection. | Low. | Process restart. | Keep as the safe complement. |
| **L1. `setActive` swizzle** (current 0.2.1) | Before activation, change `Playback`/`SoloAmbient` to `Playback` + `MixWithOthers`. | Every injected app with a matching session. | Upgrades `SoloAmbient` to `Playback` (silent-switch change); global; race; may glitch route. | None beyond injection. | Low/medium (selector stable). | Process restart; `restoreMix` on bypass. | Useful last-chance guard, insufficient alone; make opt-in and stop upgrading `SoloAmbient` silently. |
| **L2. `setCategory` swizzles + reassert** | Hook 3-arg and 4-arg `setCategory`; append `MixWithOthers` only for output-only `Playback`; reassert after category changes for a short window. | Selected apps; WebKit GPU process included. | Options may be re-cleared; route change; Now Playing eligibility changes; app may not expect mixable. | None beyond injection. | Medium (selectors/paths change; WebKit internal). | Process restart; restore original only if state matches. | **Best public-API candidate.** Needs diagnostics and per-app gating. |
| **L3. Legacy AudioSession C property** | `AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryMixWithOthers, ...)`. | Per process. | Deprecated "no longer supported" since iOS 7; may be a no-op; if it works, it is an invisible global override. | None. | High (legacy API). | Process restart. | Test-only; do not ship. |
| **L4. Suppress interruption notifications** | Swizzle `NSNotificationCenter` delivery or `AVAudioSession` private interruption handler. | Per app or globally. | Hides call/Siri/alarm interruptions; desyncs UI; audio already stopped; does not resume. | Injection; private selectors if used. | High. | Process restart. | **Reject.** |
| **L5. Victim-side auto-resume** | On interruption, if reason is another app (not call/Siri/route), reactivate and call play/resume; possibly send MediaRemote play. | Selected victim apps. | Fights the user; may resume after a call; UI/state mismatch; app-specific; may loop; may resume protected content incorrectly. | Injection; MediaRemote private if used. | High. | Process restart. | Only as an app-specific last resort; never global. |
| **L6. MediaRemote / Now Playing control** | Prevent an app from claiming Now Playing (`MRMediaRemoteSetCanBeNowPlayingApplication(false)`), or change now-playing state/commands. | Per process/global. | Breaks lock screen/Control Center/remote commands; does not necessarily stop session arbitration; private. | Likely private MediaRemote entitlements; unverified exact set. | High. | Process restart; state may persist server-side. | Not a primary mechanism; diagnostics only. |
| **L7. WebKit-specific patch** | In the GPU process, force `Playback` + `MixWithOthers` + `Default` route policy for audible media, unless capture; suppress only non-system WebKit interruption pauses. | Safari and WKWebView media. | Breaks AirPlay/PiP/Now Playing/DRM expectations; route changes; fragile across WebKit versions. | Injection into `com.apple.WebKit.GPU` (already done). | **Very high** (WebKit internals change). | Process restart. | Only if Safari is the must-win case and the product accepts breakage. |
| **L8. SpringBoard / MediaExperience** | Hook UI/now-playing/remote-control layer. | System UI. | Does not arbitrate audio sessions; may break Control Center; crash SpringBoard. | SpringBoard injection; private. | High. | Respring. | **Reject** for audio arbitration. |
| **L9. `mediaserverd` / `AudioSessionServer`** | Hook the server's session arbitration/interruption logic directly; global mixing or suppression. | All audio on device. | Calls, Siri, alarms, recording, emergency alerts, route changes, boot loop; one bug can silence the device. | Root + platform/private audio entitlements; daemon injection; exact set unknown. | **Extreme** (encrypted/private daemon, per-OS). | Requires reboot/respring; hard to guarantee. | **Reject.** |
| **L10. CallKit / voice processing** | Modify call/voice sessions to mix. | Calls/Siri/VoIP. | Echo, privacy, missed call, emergency failure; violates platform expectations. | CallKit/private. | Extreme. | Reboot. | **Never.** |
| **L11. Audio driver / PulseAudio-style server** | Replace/augment CoreAudio output with a virtual server that mixes clients. | System-wide. | iOS apps do not speak ALSA/Pulse; would need to intercept CoreAudio/mediaserverd; not a drop-in. | Driver/daemon entitlements. | Extreme. | Reboot/restore. | **Not viable** on iPadOS 15–18. |

### 3.1 Notes on specific layers

**L1/L2 are the only layers that use documented behavior.** They are also the only ones that can be shipped in a jailbreak tweak without touching system daemons. `[V]`/`[I]`

**Why L9 is unknown rather than designed:** read-only inspection of this 17.7.8 device found that `/System/Library/PrivateFrameworks/AudioSession.framework` and `AudioSessionServer.framework` contain only `Info.plist`/`_CodeSignature` (no loadable binary), and `/usr/sbin/mediaserverd` is a 210 KB binary whose plain `strings` output is largely unreadable (consistent with encryption/compression). The server-side arbitration logic is therefore not symbol-auditable here. `[V]` (local inspection); this is a reason for caution, not proof that injection is impossible. `[I]`

**L2 must handle four selectors/paths**, at minimum:

- `-setCategory:error:`
- `-setCategory:withOptions:error:`
- `-setCategory:mode:options:error:`
- `-setCategory:mode:routeSharingPolicy:options:error:`

and the C/SPI paths if an app bypasses the ObjC wrapper. `[I]`

**Do not force `PlayAndRecord`.** It is the category used by VoIP, recording, video chat, and WebKit capture. Making it mixable can change microphone/call routing and privacy behavior. The current `allowed()` exclusion is correct and should remain. `[V]`/`[I]`

**Do not force `SoloAmbient` to `Playback` without telling the user.** It makes the app audible with the Ring/Silent switch on. If concurrency is desired for a game using `SoloAmbient`, the UI must say "this can make the app play in silent mode" or skip it. `[V]`

**Do not use `Ambient` as a shortcut.** `Ambient` mixes without interrupting, but it obeys the Ring/Silent switch and is intended for non-primary audio; forcing a media app into `Ambient` can silence it or change background behavior. `[V]`

**Do not use `setPrefersNoInterruptionsFromSystemAlerts` as a mixing hack.** It is for calls/alerts, not app-vs-app, and using it to avoid call interruptions is a safety regression. `[V]`

### 3.2 What a "kill switch" must cover

- A global pref that is independent of the audio path, so a broken service can still be disabled.
- Injected clients should fail open (unity gain, original session options) when the service state is stale, not only when the user toggles.
- On disable, restore the app's original category/options only if the current state still matches what SoundDeck applied; otherwise leave the app's own state alone (the existing `matchesApplied` pattern). `[V]`
- On call/Siri/route change/recording, immediately stop forcing mix; do not auto-resume afterward.
- On reboot, default off; re-arm only after unlock and explicit user action.
- On uninstall, process restart is the restore; no daemon state to clean up.

---

## 4. Prior art and open-source landscape

| Project | What it does | License | Relevance / caveat |
|---|---|---|---|
| [VolumeMixer](https://github.com/brendonjkding/VolumeMixer) | Per-app volume on jailbroken iOS via AudioUnit/PCM hooks. | MIT. `[V]` | Proves per-process audio hooks are practical; it is **not** a concurrency mixer. SoundDeck's adapters are in the same family. |
| [VolumeMixerBoost](https://github.com/VasirakCalgux/VolumeMixerBoost) | Fork of VolumeMixer with boost. | MIT (repository page). `[V]` | Same; no concurrency guarantee. |
| [AudioMix](https://www.ios-repo-updates.com/repository/kingpuffdaddi-s-repo/package/com.kingpuffdaddi.audiomix) (KingPuffdaddi) | "Tweak to play two or more audio sources simultaneously." Rootless package, last updated 2023. | Closed source; free package; no license/source. `[V]` | Closest direct prior art. Its own description: "Doesn't work well with all apps! Sometimes the first audio still gets paused, so you will have to start it again." That is strong evidence that this is best-effort, not a universal PC-style mixer. Do not copy; no source. |
| VolumePanel (BigBoss, legacy) | Per-app volume panel (iOS 6 era). | Paid/closed. `[V]` (listing) | Historical; not a modern concurrency solution. |
| [Xios](https://github.com/MaxLeiter/jailbreak) | Wayland/X11 desktop environment for jailbroken iPad. | MIT. `[V]` (LICENSE) | Not a CoreAudio mixer. `[I]` It does not give App Store apps a PulseAudio/ALSA path. Useful as a desktop project, not as an audio-concurrency layer. |
| [PulseAudio](https://www.freedesktop.org/wiki/Software/PulseAudio/) | General-purpose sound server (LGPL). | LGPL. `[V]` | On iOS, apps use CoreAudio/mediaserverd, not ALSA/Pulse. `[I]` A Pulse server cannot see or mix App Store apps without replacing/intercepting CoreAudio; not a drop-in. |
| [Android AudioFlinger](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/services/audioflinger/) | Android's audio mixer; multiple clients are mixed by the server by default. | Apache-2.0. `[V]` | Design contrast: Android has an OS-level mixer and audio focus; iOS has session arbitration and app-level interruption semantics. You cannot port the Android model by adding a user-space mixer. |
| [react-native-video #5140](https://github.com/TheWidlarzGroup/react-native-video/issues/5140) | Documents activation-time mix decision. | Repository MIT; issue text. `[V]` | Not prior art for jailbreak, but excellent evidence that changing options after activation does not undo an interruption. |

**What the prior art suggests:** per-app gain is a solved-ish problem with process hooks; per-app **concurrency** is a different problem, and the only public attempt I found is explicitly unreliable across apps. No OSS project in this survey implements a safe, documented, universal iOS mixer. `[V]`/`[I]`

---

## 5. Safe experiment matrix

> **Do not run these experiments unattended, on a daily driver, or with real emergency calls.** The agent producing this report did not run them. They require the device owner's consent, a backup, a low volume level, and a second device for call tests. Do not start or stop the user's Music/Safari playback from automation. The Music/Safari rows are manual, user-initiated tests.

### 5.1 Fixtures and assets available in this repository

- `com.alsinas.sounddeck.toneA` / `toneB` — RemoteIO 440/880 Hz, deliberately non-mixing. `[V]`
- `com.alsinas.sounddeck.media.aq` — AudioQueue.
- `...media.avp` — AVPlayer.
- `...media.ap` — AVAudioPlayer.
- `...media.ae` — AVAudioEngine PCM.
- `...media.sbr` — AVSampleBufferAudioRenderer.
- `...media.web` — WKWebView Web Audio fixture.
- `...media.webmedia` — WKWebView HTML media/AVPlayer fixture.
- `Tests/assets/03may2020-tobefree.mp3` — CC BY-SA 4.0 piano track; `Tests/assets/safari-test.html` — minimal Safari page.
- Existing numeric harness: `Tests/run-device.py`, `run-media.py`, `run-web.py`, `run-lifecycle.py`, `run-unit.py`. `[V]`

### 5.2 Instrumentation to add in a throwaway 0.3 branch (not in 0.2.x)

A diagnostics-only dylib or log channel that records, per process and timestamp:

- bundle ID, PID, coalition, `webProcess` flag;
- `AVAudioSession.category`, `.mode`, `.categoryOptions` (hex), `.routeSharingPolicy`, `.isActive`;
- `secondaryAudioShouldBeSilencedHint`, `otherAudioPlaying`;
- `AVAudioSessionInterruptionNotification`: type, reason, options;
- `AVAudioSessionRouteChangeNotification`: reason, previous/current route;
- `AVPlayer.timeControlStatus`, `.rate`, `.reasonForWaitingToPlay`, `.error`;
- `MPNowPlayingInfoCenter.default().playbackState` (and, only if needed, private MediaRemote now-playing bundle — opt-in diagnostics);
- PCM callback counters/RMS from the existing observers;
- every `setCategory`/`setActive` hook hit with `enabled`, `mixing`, before/after options, selector variant, and error code;
- service global-state bits and freshness.

Do **not** log audio samples, media URLs, song titles, or browser history. Use a dedicated `os_log` subsystem and a bounded local ring buffer. `[I]` (privacy design)

### 5.3 Test matrix

| ID | Setup | Action | What to record | What it discriminates | Risk |
|---|---|---|---|---|---|
| T0 | Mode off. A + B fixtures. | Start A, then B. | Both sessions' category/options; A's PCM. | Baseline interruption; confirms fixtures reproduce native behavior. | Low. |
| T1 | Mode on, A + B. | Start A, then B. | Hook hits, options, both PCM. | Whether `setActive` mix works for ordinary Playback. | Low. |
| T2 | Mode on, WEB (Web Audio) + A. | Start WEB, then A. | WebKit GPU PID/category/options; A's PCM. | WebKit Ambient/WebAudio path; GPU injection. | Low. |
| T3 | Mode on, WEBM (HTML media) + A. | Start WEBM, then A. | Same; policy (`LongFormAudio`?); route changes. | WebKit Playback/LongForm path vs T2. | Low. |
| T4 | Manual: Music station playing; mode on; Safari stock MP3. | User starts Safari. | Music: interruption notification? `isActive`? `AVPlayer.rate`? `secondaryAudioShouldBeSilencedHint`? Safari: category/options/policy at activation; hook hit? | The target failure. Distinguishes server deactivation vs Music self-pause. | Medium (user media; manual). |
| T5 | Reverse: Safari playing; mode on. | User starts Music. | Safari's interruption/session state; Music's category/options. | Whether the fix is symmetric; Music as starter. | Medium. |
| T6 | Web Audio-only page (Ambient) + Music. | User starts the page. | Music state; page session category. | If Ambient mixes but `<audio>` does not, long-form/Playback is implicated. | Low/medium. |
| T7 | Podcasts (SpokenAudio) + a navigation-style prompt fixture. | Start prompt. | Podcast state; prompt options. | `InterruptSpokenAudioAndMixWithOthers` semantics; ensure not over-applied. | Low. |
| T8 | A + B; wired headphones, BT A2DP, BT HFP, AirPlay. | Plug/unplug/route change. | Route reason; session active; options; PCM. | Route-change fragility; HFP vs A2DP. | Medium (hearing/route). |
| T9 | A + B; lock/unlock; background; Split View. | Background one app; lock; unlock. | Session active; PCM; interruption. | Suspension/background restrictions. | Low. |
| T10 | Mode on; incoming call (second device), outgoing call to voicemail, Siri, alarm/timer, Voice Memos recording. | Trigger each; decline/end. | Session category; interruption reason; whether forcing stops; recovery. | Call/Siri/recording safety; must suspend, not mix. | **High** — user present; no emergency numbers. |
| T11 | Mode on; A + B. | Toggle off; `sdctl disable`; kill service; uninstall; respring; reboot. | Options restored; PCM unity; no stuck mix; app relaunch. | Kill switch and reversibility. | Medium. |
| T12 | A + B, 30 min. | Soak. | CPU, RSS, battery/thermal, PCM continuity. | Battery/thermal; long-run stability. | Low. |

### 5.4 Detection decision tree

Use these observations together; none alone is conclusive.

1. **`interruptionNotification` began + `isActive == false` + PCM stopped**
   → server-side deactivation. The starter was not mixable (or another arbitration rule applied). Focus on the starter's category/options/timing.

2. **No interruption notification + `isActive == true` + player `rate == 0`**
   → the app paused itself, or MediaRemote/Now Playing changed, or the app muted its secondary audio. This is not a session interruption.

3. **`interruptionNotification` began + `isActive == true`**
   → unusual; log it. Could be a notification without deactivation, a race, or an app-level synthetic notification. Do not assume.

4. **`secondaryAudioShouldBeSilencedHint == true` while the mode is on and the starter is playing**
   → another app with a **non-mixable** session is still playing. The starter is not mixable, or the victim is a different app. `[V]` (property definition)

5. **Starter's `categoryOptions` lacks `MixWithOthers` at `setActive`**
   → hook/timing/selector problem (candidate #1/#2).

6. **Starter's category is `PlayAndRecord`**
   → excluded by design; do not force it. Test without capture or accept that this app cannot be made concurrent. (candidate #3)

7. **Starter is `Playback` + `MixWithOthers` at activation, victim still stops, victim has no interruption notification**
   → app-level/Now Playing/MediaRemote, not session arbitration. (candidate #5)

8. **Starter is `Playback` + `MixWithOthers`, victim has interruption notification and `isActive == false`**
   → the server did not honor mixability for this pair; suspect long-form policy, voice priority, or a private rule. (candidate #4)

### 5.5 Measurement details

- Use `secondaryAudioShouldBeSilencedHint` as a cheap live indicator; it is defined as true when another app with a non-mixable session is playing. `[V]`
- Use `AVAudioSession.isActive` plus the PCM callback counter to separate "session deactivated" from "player paused but session alive." `[V]`
- Use `AVPlayer.timeControlStatus`/`rate`/`reasonForWaitingToPlay` to distinguish user pause, buffering, and interruption. `[V]`
- Use route-change reason `OldDeviceUnavailable` to avoid misattributing a headphone unplug to the concurrency test. `[V]`
- Timestamp everything with a monotonic clock and the wall clock; cross-correlate Safari activation, Music interruption, and route changes. `[I]`
- Do not measure "success" by an app's UI play button alone. A playing UI with an inactive session is a false positive. `[V]` (design consequence)

### 5.6 Safety rules for the test matrix

- No emergency calls (911/112/etc.), no real emergency alerts, no alarm tests that could trigger a real siren/alert at volume.
- Use a second device or a carrier voicemail/test number for call tests; keep the device owner present.
- Keep volume low; do not use headphones at high volume; simultaneous sources can sum and clip.
- Stop if a crash loop, respring loop, or boot loop begins; use the documented recovery path and uninstall.
- One variable per run; record baseline before enabling the mode.
- Do not run the Safari/Music test while the user is listening to something they care about; the test intentionally stops playback.

---

## 6. Risk assessment

| Risk | Likelihood | Impact | Why | Mitigation |
|---|---|---|---|---|
| **Call audio mixed/ducked/missed** | Low if `Record`/`PlayAndRecord` excluded; medium if not | High | Call sessions use voice processing and priority; forcing mix can break routing or hide the call. | Never touch `Record`/`PlayAndRecord`/`MultiRoute`/VoiceProcessingIO; detect CallKit/telephony and suspend; test with a second device; kill switch. |
| **Siri/voice assistant interference** | Medium | Medium | Siri uses its own session; forcing mix can confuse ducking/recognition. | Exclude Siri bundles and voice modes; suspend on interruption; never suppress Siri notifications. |
| **Recording privacy / mic indicator mismatch** | Low if excluded; high if forced | High | `PlayAndRecord` is both playback and capture; mixing it can change input routing and privacy expectations. | Hard exclusion; no mic access; no VoiceProcessingIO hooks; audit. |
| **Emergency alerts suppressed** | Very low if no notification suppression; catastrophic if daemon-level | Critical | Alerts must always take priority; `setPrefersNoInterruptionsFromSystemAlerts` is not a license to hide emergencies. | Never suppress system interruptions; never touch `mediaserverd`; explicit safety boundary in code/UI. |
| **Hearing damage / clipping** | Medium | High | The OS sums concurrent sources; two full-scale streams can exceed safe level. SoundDeck does not currently apply a summing limiter. | Warn; default low volume; per-app gain; optional master headroom (e.g., −6 dB) when >1 stream; do not auto-raise volume. |
| **Battery/thermal** | Medium | Medium | Multiple decoders, radios, and audio pipelines stay active. | Auto-expire; only selected apps; no background daemon; soak test; show mode status. |
| **Crash loop / respring loop** | Low for app-process hooks; medium for WebKit; high for daemon | High | A bad swizzle in a system process can crash every launch. | App-process only; fail-open; watchdog; no SpringBoard/mediaserverd; test on a spare device. |
| **Boot loop** | Very low without daemon; high with daemon | Critical | Daemon injection can prevent boot. | Do not inject `mediaserverd`/launchd; keep all changes in user processes. |
| **DRM/protected content** | Medium | Medium | Forcing mix/route policy may break protected playback or cause silence. | Do not alter protected/remote paths; fall back; test with a protected sample only if the user approves. |
| **AirPlay/Bluetooth/CarPlay route breakage** | Medium | Medium | Category/route policy changes can reroute audio or break HFP/A2DP. | Preserve route policy; test routes; restore on change; no global route override. |
| **Now Playing/lock-screen confusion** | Medium | Low/medium | Mixable sessions are not good Now Playing candidates; controls may target the wrong app. | Explain in UI; do not force mix on the primary media app unless the user chooses it; test CC/lock screen. |
| **Privacy/log leakage** | Low | Medium | Diagnostics could log app usage/media metadata. | No audio, URLs, titles, or history; bounded local logs; opt-in; retention limit. |
| **Legal/App Store** | N/A for App Store (jailbreak) | Medium | Jailbreak distribution; Apple EULA/ToS; third-party app behavior; no DRM circumvention. | Ship only via jailbreak repo; clear experimental license; no App Store claim; respect third-party terms. |
| **User intent / confusion** | High | Medium | Two apps playing at once is unusual; users may think audio is broken. | Explicit toggle, per-app labels, auto-expire, easy stop, explain "some apps will still pause." |

**Safety bottom line:** the only acceptable design is one that cannot affect calls, recording, Siri, alarms, or emergency audio, and that fails open. That rules out daemon-level arbitration and notification suppression. `[I]`

**Legal/App Store note:** this cannot be an App Store feature. It depends on jailbreak injection and, for any broad version, undocumented behavior. Distribution is jailbreak-only; the repository's MIT license and Apple's software license/third-party app terms still apply. Do not use the feature to circumvent DRM or protected-content rules, and do not present it as an Apple-supported capability. The UI should say "experimental, unsupported, some apps will still pause." `[I]`

---

## 7. Proposed design options and recommendation

### 7.1 Option 0 — do not implement (recommended for 0.2.x)

Keep the current product decision: per-app gain while playing, best-effort `MixWithOthers`, no claim of universal concurrency. Document the limitation. This is the lowest-risk choice and matches the existing release notes.

**Pros:** no new failure modes; no call/recording risk; no support burden. **Cons:** users who want Music + Safari together are not served.

### 7.2 Option A — per-app "may start without stopping others" (narrowest viable experiment)

**User model:** a per-app switch: "Allow this app to start without stopping other audio." Default off. The user enables it for the app they want to be "polite" (for example Safari, a game, a metronome), not for the app they want to protect.

**Mechanism:**

1. In the selected app's process (including WebKit GPU if the app is WebKit-based), before activation:
   - If category is `Playback` and output-only: add `MixWithOthers`, remove `DuckOthers`.
   - If category is `Ambient`: already mixable; no change.
   - If category is `SoloAmbient`: **skip** by default, or require an explicit "also play in silent mode" confirmation. Do not silently upgrade.
   - If category is `Record`, `PlayAndRecord`, `MultiRoute`, or a voice mode: skip unconditionally.
2. Hook all four `setCategory` variants; normalize idempotently, preserving the app's mode and route-sharing policy (never invent a policy just to add an option). The convenience setters may call the richer setter internally, so guard against recursion/double application. Reassert the option only for the selected app and only while the mode is on. Use a generation counter/short window so WebKit's own `updateSessionState` cannot silently clear it.
3. Do not touch the victim app, do not suppress interruption notifications, do not touch MediaRemote.
4. Auto-expire after 10 minutes or on lock; restore original options if still matching.
5. Kill switch in the app and Control Center; `sdctl concurrency 0`.

**Pros:** only the starter is modified; no victim-side hacks; no daemon; public API; reversible. **Cons:** does not help apps that use `PlayAndRecord` (WebKit capture), protected/remote audio, or apps that self-pause on Now Playing; still best-effort.

**This is the design to test first.** `[I]`

### 7.2.1 Ducking variant (safer UX)

Instead of full mixing, set `DuckOthers` (which also implies `MixWithOthers`) on the starter. The other app keeps playing but at reduced volume. This reduces summing/clipping and is less startling than two full-volume sources. It still changes the other app's volume, and some apps may not restore full volume until the starter deactivates; test that. This is a reasonable default if the product goal is "don't pause" rather than "both at full volume." `[V]` (option semantics) `[I]` (UX recommendation)

### 7.3 Option B — per-pair rule ("keep A playing when B starts")

**User model:** "Keep [Music] playing when [Safari] starts." This is closer to PC-style intent and avoids making every app permanently mixable.

**Mechanism:** same as Option A, but the service publishes a small "protected apps" set; B's injected code only forces mixability when A is currently active (or when the user explicitly armed the pair). No victim-side code. The pair is stored in prefs and expires.

**Pros:** clearer intent; less global behavior change. **Cons:** more state/IPC; still cannot overcome `PlayAndRecord`/long-form/Now Playing; the "A is active" check can race.

### 7.4 Option C — Safari/WebKit-specific patch

Patch the WebKit GPU process's `AudioSessionIOS`/`MediaSessionManagerCocoa` behavior:

- force `Playback` + `MixWithOthers` + `Default` route policy for audible media, unless capture;
- prevent WebKit's own interruption pause only for app-origin interruptions (never calls/Siri).

**Pros:** highest chance for the specific Music + Safari case. **Cons:** WebKit internals are private and change per OS; breaks AirPlay/PiP/Now Playing/DRM expectations; likely unacceptable for a general product. Only consider if Safari is a must-win and users accept breakage.

### 7.5 Option D — daemon/global arbitration

Hook `mediaserverd`/`AudioSessionServer` or suppress system interruptions globally. **Reject.** It is the only way to get a true universal guarantee, but it is private, version-fragile, and can break calls/emergency audio or boot the device. `[I]`

### 7.6 Recommended kill-switch design

- Global `concurrency` pref, default **off**; per-app `concurrent` pref, default **off**.
- `disabled` remains the master bypass; it must restore unity gain and stop forcing mix.
- Service heartbeat freshness: if the service is stale for >5 s, clients fail open and stop forcing mix.
- Auto-expire: 10 minutes, screen lock, call/Siri/recording, or route change.
- On restore: only revert if current category/options still match what SoundDeck applied; otherwise leave the app's own state.
- No persistence of "on" across reboot; re-arm after unlock.
- UI: one sentence of honest copy — "Experimental. Some apps will still pause. Calls, Siri, alarms, and recording always take priority. Turns off automatically in 10 minutes."

### 7.7 Entitlements and packaging

- App-process/WebKit-GPU swizzles need only the existing jailbreak injection path (ElleKit) and the existing signing setup. `[V]`
- No `mediaserverd`, SpringBoard audio, CallKit, or MediaRemote entitlement should be added for this feature. `[I]`
- Keep the rootless `/var/jb` layout; no system partition writes; uninstall leaves no daemon state. `[V]`
- If a future design needs private MediaRemote calls, treat that as a separate, explicitly experimental package with its own risk review; do not fold it into the mixer. `[I]`

---

## 8. SoundDeck code-path map

### 8.1 Files and responsibilities

| File | Key symbols / lines | Role | Concurrency relevance |
|---|---|---|---|
| `Shared/SDProtocol.h` | `SDConfig` (`:20-27`), bit 12 `mixing`, `SDGlobalState`, `SDClientState` | Cross-process config/state via notifyd. | Add a per-app concurrency bit/pref here; do not overload `mixing` silently. |
| `Shared/SDPreferences.m` | defaults (`:7`), `SDSanitizePrefs` (`:5-25`), atomic write (`:27-50`) | Preference validation/persistence. | New keys must be sanitized and default off. |
| `Shared/SDIdentity.h` | `SDExcludedBundle` (`:19-23`), `SDCoalitionKey`, `SDResponsiblePID` | Excludes SpringBoard/phone/FaceTime/Siri/etc.; coalition identity. | Safety boundary already excludes call/Siri system bundles; preserve. |
| `Backend/Runtime.mm` | `enabled/mixing` (`:12`), `allowed` (`:198`), `applyMix` (`:199-204`), `restoreMix` (`:205-209`), `setActive` (`:210-213`), `update` (`:214-222`), constructor (`:223-262`), hook (`:251`), WebKit heartbeat (`:188-191`) | Per-process audio control and session forcing. | Main change point for L1/L2. |
| `Backend/NativeAdapters.inc.mm` | `installNative` (`:118-136`), `applyNative` (`:92-96`) | AudioQueue/AVPlayer/AVAudioPlayer/sample-buffer adapters. | Gain path; independent of concurrency. |
| `Backend/AUProviders.inc.mm` | provider/engine hooks (81 lines) | AVAudioEngine/AU PCM. | Gain path; independent. |
| `Backend/Service.m` | `reload`, `snapshot`, `webOwners`, coalition resolution (`:1-138`) | Discovers PIDs, attributes WebKit subprocesses, publishes state. | New per-app config must be published here; no new daemon. |
| `ControlCenter/SDControlCenter.m` | rows/sliders (`:112-145`) | Control Center UI. | Add a toggle only if the design ships; keep zero-slider mute semantics. |
| `ControlCenter/SDBridge.m` | SpringBoard presentation/dismiss only | UI bridge; no audio hooks. | Do not turn this into an audio control point. |
| `App/SDMasterVolume.m` | `AVSystemController` volume (`:1-27`) | Master media volume only. | Not a concurrency mechanism. |
| `Tools/sdctl.m` | `mixing 0/1` (`:29`), `disable`/`enable` (`:31-32`) | QA/control CLI. | Add `concurrency`/per-app diagnostics for tests. |
| `Packaging/*` | rootless install, postinst/prerm | Install/remove. | No mediaserverd/boot changes; keep recovery. |

### 8.2 Data flow

```
App process (injected)
  ├─ PCM adapters / native volume adapters ──► per-app gain (existing)
  ├─ AVAudioSession setActive (hook) ────────► applyMix (best-effort)
  └─ notify client state ────────────────────► SoundDeck service
                                                     │
WebKit GPU process (injected)                        ├─ discovers PIDs/coalitions
  ├─ same hooks, webAgent=1                          ├─ groups web process → host app
  ├─ 0.5 s polling heartbeat                         ├─ publishes SD_GLOBAL / per-app gains
  └─ notify client state ────────────────────────────┘
                                                     │
                                             App / Control Center UI
                                               (rows, master volume)
```

### 8.3 Current session path, step by step

1. App calls `-[AVAudioSession setActive:YES withOptions:... error:]`.
2. SoundDeck's `setActive` hook runs (`Runtime.mm:210`):
   - `playbackAllowed = allowed(self)`; if the category is `Record`/`PlayAndRecord`/`MultiRoute`, gain will be unity and mix is skipped.
   - `update(false)` reads global notify state; `enabled` may be false at this point.
   - If `enabled && mixing`, `applyMix(self)` runs before the original activation.
3. `applyMix`:
   - rejects non-`Playback`/`SoloAmbient`;
   - saves the original category/mode/options if they differ from the last applied state;
   - changes `SoloAmbient` to `Playback`, ORs `MixWithOthers`, clears `DuckOthers`;
   - calls `setCategory:mode:options:error:` and records the applied state.
4. Original `setActive` runs. The server decides based on the category/options now in effect.
5. If activation succeeds, `sessionIsActive = true`; later `update()` may call `applyMix` again if the global mode just turned on.
6. On global disable/mixing off, `restoreMix` restores the saved state only if the session still matches what SoundDeck applied.

**Where the current path fails for Safari:** steps 2–3 are skipped if `enabled` is still false when the WebKit GPU process first activates; step 3 uses the three-argument setter, while WebKit uses the four-argument setter; and WebKit can reassert `options=0` later. `[V]` for code; `[I]` for the failure mapping.

### 8.4 Where a narrow design would hook

- `Runtime.mm:251`: keep the `setActive` hook.
- Add hooks for all four `setCategory` selectors, in both app and WebKit agents; normalize idempotently and guard against recursion through convenience wrappers.
- Gate on a per-app `concurrent` flag read from the global/per-app notify state; never on a global default.
- Do not change `SoloAmbient` unless the user explicitly opts into the silent-switch tradeoff.
- Reassert only while the app is active and the mode is on; use a generation counter to avoid fighting the app forever.
- `Service.m:reload`: publish the new per-app flag; `SDProtocol.h`: define bits; `SDPreferences.m`: sanitize/default off.
- `ControlCenter`/`App`: one toggle per row plus a master kill switch; `sdctl` for QA.

---

## 9. Verdict, confidence, and missing evidence

### 9.1 Verdict

**Feasible only app-specific, as a best-effort opt-in mode. Universal PC-style concurrency is not feasible safely with public APIs on iPadOS 15–18.**

- **For ordinary output-only `Playback` apps in a process SoundDeck injects:** plausible and partially demonstrated (fixtures). Confidence: **medium-high**.
- **For Music + Safari specifically:** unproven; the one live failure is consistent with a fixable timing/selector gap, but also with WebKit long-form/Now Playing behavior. Confidence in a reliable fix: **low** without more diagnostics.
- **For calls/Siri/recording/emergency:** must remain excluded. Confidence: **high** that forcing them is unsafe.
- **For a universal guarantee via `mediaserverd`:** technically possible in principle, practically unacceptable. Confidence: **high** that it should not be attempted.

### 9.2 What evidence is missing

1. The exact `category`, `mode`, `categoryOptions`, `routeSharingPolicy`, and `isActive` state of **Music** and **Safari's GPU process** at the moment Music stops on 17.7.8. `[U]`
2. Whether Safari's first `setActive` in the GPU process is reached by SoundDeck's hook while `enabled` is true; whether `applyMix` runs before or after WebKit's own `setCategory`. `[U]`
3. Whether Music receives `AVAudioSessionInterruptionNotification` and whether its session becomes inactive, or whether its player pauses while the session stays active. `[U]`
4. Whether `secondaryAudioShouldBeSilencedHint` flips at the failure. `[U]`
5. Whether `LongFormAudio` is the blocking rule (test Web Audio-only vs `<audio>`). `[U]`
6. Whether WebKit's `PlayAndRecord` path is active (capture/permissions). `[U]`
7. Behavior on iOS 15, 16, and 18, and on other devices. `[U]`
8. Call/Siri/recording/route-change/battery tests. `[U]`
9. Legal/product review of shipping an experimental concurrency mode in a jailbreak package. `[U]`

### 9.3 Recommendation

1. **Do not ship a universal concurrency mode in 0.2.x.** Keep the current product decision and documentation.
2. **If the product wants to pursue it:** create a 0.3 experimental branch with **Option A** (per-app "may start without stopping others") and diagnostics, not daemon hooks, not notification suppression.
3. **First milestone is diagnostic, not audible:** prove, with logs, whether Safari is `Playback` + `MixWithOthers` at activation and whether Music is being deactivated. If Safari is not mixable at activation, fix the timing/selector; if it is mixable and Music still stops, the problem is long-form/Now Playing/private arbitration and the public-API design is unlikely to succeed.
4. **Timebox:** if Music + Safari cannot be made to coexist with a correctly timed, four-argument, per-app hook on this device, stop. Do not escalate to `mediaserverd` for a consumer feature.
5. **If it ships:** default off, per-app, auto-expire, kill switch, no call/recording/Siri paths, no system-alert suppression, clear "some apps will still pause" copy.

### 9.4 Limitations of this research

- No playback was started, stopped, or listened to for this report; no acoustic or PCM measurements were taken. The only live Music/Safari observation is the project's existing note, not an independent replication. `[V]` (scope statement)
- The WebKit source inspected is the project's main branch (October 2026), not the exact WebKit build shipped in iPadOS 17.7.8. The architecture is likely similar, but selector names, process layout, and policy details can differ. `[I]`
- `AudioSession.framework`/`AudioSessionServer.framework` are stubs on this device and `mediaserverd` is not symbol-readable in a plain strings pass; the server's exact arbitration rules are not audited. `[V]`/`[U]`
- The unpublished `setCategory` branch is absent from git and cannot be audited. `[V]`
- One device, one jailbreak, one OS build; no iOS 15/16/18, other iPads, or arm64e testing. `[U]`

---

## 10. References

### Apple documentation and SDK

- [AVAudioSession.CategoryOptions.mixWithOthers](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers) — activation-time semantics; "Clearing this option ... interrupts other audio sessions."
- [AVAudioSession.CategoryOptions.duckOthers](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/duckothers)
- [AVAudioSession.CategoryOptions.interruptSpokenAudioAndMixWithOthers](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/interruptspokenaudioandmixwithothers)
- [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)
- [AVAudioSession.interruptionNotification](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification)
- [AVAudioSession.setCategory(_:mode:options:)](<https://developer.apple.com/documentation/avfaudio/avaudiosession/setcategory(_:mode:options:)>)
- [AVAudioSession.setActive(_:withOptions:)](<https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive(_:withoptions:)>)
- [AVAudioSession.secondaryAudioShouldBeSilencedHint](https://developer.apple.com/documentation/avfaudio/avaudiosession/secondaryaudioshouldbesilencedhint)
- [WWDC22: Explore media metadata publishing and playback interactions](https://developer.apple.com/videos/play/wwdc2022/110338/) — Now Playing eligibility and non-mixable sessions.
- Archived *Audio Session Programming Guide*:
  - [Activating an Audio Session](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/ConfiguringanAudioSession/ConfiguringanAudioSession.html)
  - [Responding to Interruptions](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html)
  - [Audio Session Categories and Modes](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioSessionCategoriesandModes/AudioSessionCategoriesandModes.html)
- Local SDK header evidence: `/var/jb/usr/share/SDKs/iPhoneOS.sdk/System/Library/Frameworks/AVFAudio.framework/Headers/AVAudioSessionTypes.h` (category option docs; `MixWithOthers` validity; non-sticky options) and `AVAudioSession.h` (`setPrefersNoInterruptionsFromSystemAlerts`, `InsufficientPriority`, `secondaryAudioShouldBeSilencedHint`). `[V]`

### WebKit source (inspected October 2026; OS 17.7.8 may differ)

- [AudioSessionIOS.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/ios/AudioSessionIOS.mm) — category mapping, four-argument `setCategory`, interruption observer.
- [AudioSessionCocoa.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/cocoa/AudioSessionCocoa.mm) — `setActive:YES withOptions:0` on a serial activation queue.
- [MediaSessionManagerCocoa.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/cocoa/MediaSessionManagerCocoa.mm) — category selection, LongFormAudio, MediaRemote now-playing.
- [MediaSessionManagerIOS.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/ios/MediaSessionManagerIOS.mm) — background/concurrent playback restrictions, interruption observer.
- [MediaSessionHelperIOS.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/ios/MediaSessionHelperIOS.mm) — `beginReceivingRemoteControlEvents`, host PID attribution, route changes.

### Community / prior art

- [react-native-video issue #5140](https://github.com/TheWidlarzGroup/react-native-video/issues/5140) — activation-time mix decision.
- [VolumeMixer](https://github.com/brendonjkding/VolumeMixer) — MIT; per-app volume, not concurrency.
- [VolumeMixerBoost](https://github.com/VasirakCalgux/VolumeMixerBoost) — MIT; fork.
- [AudioMix package](https://www.ios-repo-updates.com/repository/kingpuffdaddi-s-repo/package/com.kingpuffdaddi.audiomix) — closed source; explicit "doesn't work well with all apps" caveat.
- [Xios](https://github.com/MaxLeiter/jailbreak) — MIT; desktop environment, not a CoreAudio mixer.
- [PulseAudio](https://www.freedesktop.org/wiki/Software/PulseAudio/) — LGPL; not a drop-in for iOS.
- [Android AudioFlinger](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/services/audioflinger/) — Apache-2.0; contrast with iOS session arbitration.

### SoundDeck repository evidence

- `Backend/Runtime.mm`, `Backend/Service.m`, `Backend/NativeAdapters.inc.mm`, `Backend/AUProviders.inc.mm`.
- `Shared/SDProtocol.h`, `Shared/SDPreferences.m`, `Shared/SDIdentity.h`.
- `ControlCenter/SDBridge.m`, `ControlCenter/SDControlCenter.m`, `App/SDMasterVolume.m`, `Tools/sdctl.m`.
- `docs/ARCHITECTURE.md`, `docs/COMPATIBILITY.md`, `docs/TESTING.md`, `RELEASE_NOTES.md`.
- `Tests/run-device.py`, `Tests/run-media.py`, `Tests/run-web.py`, `Tests/run-lifecycle.py`, `Tests/assets/README.md`.
- Build filters: `build/stage/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.plist` (`com.apple.UIKit`) and `SoundDeckWebKit.plist` (`com.apple.WebKit.WebContent`, `com.apple.WebKit.GPU`).

---

## Appendix A — Short claim ledger

| Claim | Status |
|---|---|
| Interruption is the deactivation of the victim's session; audio stops before the notification. | `[V]` Apple archived guide. |
| `MixWithOthers` controls whether the **starter** interrupts or mixes, and is evaluated at activation. | `[V]` SDK header + Apple docs + react-native-video issue. |
| `MixWithOthers` is valid only for `Playback`, `PlayAndRecord`, `MultiRoute`. | `[V]` SDK header. |
| Options are not sticky across category changes. | `[V]` SDK header. |
| `SoloAmbient` is silenced by the Ring/Silent switch; `Playback` is not. | `[V]` Apple category table. |
| WebKit uses `Playback` for `<audio>`/video, `PlayAndRecord` with capture, `Ambient` for Web Audio-only; uses `LongFormAudio` and the four-argument `setCategory`; activates with `setActive:YES withOptions:0`. | `[V]` WebKit source (build may differ). |
| WebKit observes interruptions and pauses its media sessions. | `[V]` WebKit source. |
| SoundDeck 0.2.1 already applies `MixWithOthers` at `setActive`, default on, but does not hook `setCategory` and has an `enabled` race. | `[V]` repository code. |
| The failed setCategory trial is not in git history and cannot be audited. | `[V]` repository inspection. |
| Safari's exact session state at the failure is unknown. | `[U]` |
| Music's exact session state and whether it self-pauses are unknown. | `[U]` |
| LongFormAudio arbitration between two long-form clients is undocumented. | `[U]` |
| A universal daemon-level mixer would be private, fragile, and unsafe for calls/emergency audio. | `[I]` (strong inference). |
| A per-app, output-only, correctly timed hook is the narrowest public-API design worth testing. | `[I]` recommendation. |

## Appendix B — What would change the verdict

- **Toward "feasible"**: diagnostics show Safari at activation is `Playback` + `MixWithOthers` and Music still stops with no interruption notification and an active session; a victim-side/Now Playing fix is then needed, which is app-specific and riskier.
- **Toward "unfeasible"**: diagnostics show Safari at activation is `Playback` + `MixWithOthers`, Music receives an interruption and becomes inactive, and the server still refuses to mix the pair; that indicates a private long-form/priority rule. At that point, only WebKit-specific or daemon-level work could help, and both are out of scope for 0.2.x.
- **No change**: calls/Siri/recording remain excluded; any design that touches them should be rejected regardless of mixing results.
