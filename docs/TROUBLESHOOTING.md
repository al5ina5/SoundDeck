# Troubleshooting and rollback

## A slider has no effect

1. Confirm the jailbreak and ElleKit are active.
2. Enroll the actual application with **+**, then restart that app. Existing processes cannot acquire a newly installed injection filter automatically.
3. Run `sdctl status`. A Saved row is not a fabricated active audio session.
4. Check [compatibility](COMPATIBILITY.md). Safari's media subprocess, AudioQueue and unwrapped AVAudioEngine graphs are not supported. Do not keep trying to fix a remotely rendered audio path with a master-volume setter.

The AVPlayer path is experimental and unverified. App Store apps may use entirely different engines or stop playback themselves. A successful launch or an advancing player clock alone is not proof of audible gain control.

## No simultaneous audio

Turn on **Allow simultaneous playback**, then restart playback in each enrolled supported app. Only playback/solo-ambient sessions are modified. Recording and calls are excluded. Some apps intentionally pause themselves in the background; this adapter cannot override arbitrary app logic.

## Service unavailable

```sh
sdctl status
sudo launchctl print system/com.alsinas.sounddeck
sudo launchctl bootout system/com.alsinas.sounddeck
sudo launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.alsinas.sounddeck.plist
```

On this bootstrap launchctl may print a `user/501` proxy-domain warning even for the system service command. The inspected job must be `com.alsinas.sounddeck` with program `/var/jb/usr/libexec/sounddeckd`.

Clients should bypass automatically after about five seconds without the service's global heartbeat. Restart only affected playback apps if necessary. Do not restart audio daemons or respring blindly.

## Emergency disable

```sh
sdctl disable
```

If an app crashes too early to receive bypass, prevent further injection and stop the service that maintains the filter:

```sh
sudo launchctl bootout system/com.alsinas.sounddeck
sudo mv /var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.plist \
  /var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.plist.disabled
```

Restart only the affected application. No SpringBoard or audio daemon is injected by SoundDeck. To re-enable after resolving the problem, restore the `.plist`, bootstrap the service, run `sdctl enable`, then restart the enrolled app.

## Uninstall

```sh
sdctl disable
sudo apt remove com.alsinas.sounddeck.tests com.alsinas.sounddeck
```

The pre-removal script sends bypass before unloading the service. Already-loaded code cannot be unmapped safely from a running foreign process; restarting the app finishes restoration. Preferences remain at `/var/mobile/Library/SoundDeck/preferences.plist`. Delete that **specific SoundDeck preference file** manually only if you deliberately want to forget saved gains/enrollment. No personal media or app data is modified by uninstall.

## Diagnostics

`sdctl status` prints fresh service/client status, actual numeric PCM RMS where available, and service resource counters. `sdctl capture` asks SoundDeck to capture its own foreground view hierarchy into `/var/mobile/Library/SoundDeck/capture.png`. This is opt-in and captures no other application's content.

Do not attach full device crash archives to public issues. Share only sanitized SoundDeck-specific evidence. There is no microphone recording or human listening confirmation in automated results.
