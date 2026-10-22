# Local build and test procedure

## Toolchain used

- Procursus Clang 16 / native arm64, local iPhoneOS SDK (`/var/jb/usr/share/SDKs/iPhoneOS.sdk`), local Foundation/UIKit/framework stubs.
- ldid, odcctools (`install_name_tool`, `otool`), dpkg/dpkg-deb, Python 3, rootless palera1n, ElleKit 1.2, uikittools and CCSupport.

No remote compiler, Apple signing account/certificate, SDK download or external runner was needed. SDK and jailbreak libraries are environment prerequisites, not committed.

## Normal package

```sh
export SDK=/var/jb/usr/share/SDKs/iPhoneOS.sdk
bash build.sh
python3 Tools/validate-package.py packages/com.alsinas.sounddeck_0.2.1_iphoneos-arm64.deb
sudo dpkg -i packages/com.alsinas.sounddeck_0.2.1_iphoneos-arm64.deb
```

Executables receive local ldid signatures and payload paths are rooted under `/var/jb`; architecture is `iphoneos-arm64`. The normal package does not include scripted UI controls or fixture apps. Build normal after QA before release.

The local ElleKit substrate alias advertises a rootful path; the build normalizes it to `@rpath/libellekit.dylib` and embeds `/var/jb/usr/lib` as the runtime path before signing. The build recreates generated staging trees and native icon assets; procedure is repeatable, byte-identical output is not claimed.

## QA packages and suites

```sh
bash build.sh --tests
python3 Tests/run-unit.py
sudo dpkg -i packages/com.alsinas.sounddeck_0.2.1_qa_iphoneos-arm64.deb \
  packages/com.alsinas.sounddeck.tests_0.2.1_iphoneos-arm64.deb
python3 Tests/run-device.py
python3 Tests/run-media.py
python3 Tests/run-web.py
python3 Tests/run-ui.py
```

Run device suites serially; they launch/kill fixtures and modify only SoundDeck fixture gains/mutes, mixing/bypass settings and master media volume (which is restored). `--tests` enables compile-time-only scripted hooks and adds the separate optional fixture package. Fixtures play low-level generated test signals only when explicitly launched. UI scripts send real UIKit/Control Center control actions, not physical touches. The UI suite changes and restores system master volume by default; set `SD_SKIP_MASTER_TEST=1` when user playback may be active. The portrait request may be rejected by the current windowing mode and is recorded rather than bypassed by changing system settings.

## Lifecycle suite

After building the normal package and keeping the optional fixture package installed:

```sh
python3 Tests/run-lifecycle.py
```

Read the script first. It stops the SoundDeck service, exercises watchdog recovery, upgrades, temporarily removes only SoundDeck using `dpkg --force-depends` because its own QA fixture package depends on it, then reinstalls SoundDeck in `finally`. Do not interrupt the temporary removal interval. It does not uninstall or modify unrelated packages.

Generated local reports under `Tests/results-local/` are Git-ignored. Copy only sanitized measurements into `docs/reports/`; exclude credentials, full device logs, private app data and unrelated diagnostics.
