# Troubleshooting and rollback

## A slider has no effect

1. Confirm the rootless jailbreak, ElleKit and CCSupport are active.
2. Start playback. SoundDeck discovers supported active outputs automatically; there is no enrollment action. A saved gain is not proof the current output is controllable.
3. Read `sdctl status`: inspect the app's active/path/controllable fields and whether telemetry is fresh.
4. Check the [compatibility matrix](COMPATIBILITY.md). A remotely rendered, protected, unwrapped or app-specific path may bypass every tested adapter. Do not try to solve per-app control with the system master slider.
5. Restart that app after installing/upgrading SoundDeck.

The fixtures verify concrete paths, not every commercial app. A successful app launch/player clock is not proof of audible gain; published results distinguish PCM measurement from native parameter verification and human listening.

## Control Center module missing

SoundDeck attempts to add only its own CCSupport module identifier while retaining existing layout/reordering. Confirm CCSupport is installed, then restart SpringBoard or use Settings > Control Center. `sdctl cc-install` retries the registration; `sdctl cc-remove` removes only SoundDeck's entry. The original layout backup is stored at `/var/mobile/Library/SoundDeck/cc-layout-backup.plist`.

## No simultaneous audio

The setting affects eligible playback/solo-ambient sessions only. Recording, calls and voice-processing categories are intentionally excluded. Some apps pause themselves when backgrounded or explicitly refuse concurrent playback; SoundDeck cannot override app logic.

## Service unavailable

```sh
sdctl status
sudo launchctl print system/com.alsinas.sounddeck
sudo launchctl bootout system/com.alsinas.sounddeck
sudo launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.alsinas.sounddeck.plist
```

A client fails open to unity after about five seconds without fresh global service state. Restart affected playback apps if needed. Do not restart audio daemons or respring blindly.

## Emergency disable

```sh
sdctl disable
```

If an app crashes before it can receive bypass, prevent further injection and stop the service that maintains the filter:

```sh
sudo launchctl bootout system/com.alsinas.sounddeck
sudo mv /var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.plist \
  /var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.plist.disabled
```

Restart only the affected app. To re-enable, restore that `.plist`, bootstrap the service, run `sdctl enable`, then restart the app.

## Uninstall and diagnostics

```sh
sdctl disable
sudo apt remove com.alsinas.sounddeck.tests com.alsinas.sounddeck
```

Removal sends bypass, removes SoundDeck's own CCSupport entry and preserves SoundDeck preferences. Already-loaded code cannot be unmapped safely; restarting affected apps finishes restoration. No personal media/app data is removed.

`sdctl status` shows current per-app telemetry and service counters. `sdctl capture` captures only SoundDeck's own foreground view into `/var/mobile/Library/SoundDeck/capture.png`. Do not attach full device crash archives to public issues; share sanitized SoundDeck-specific measurements only.
