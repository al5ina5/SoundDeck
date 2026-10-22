# Local build and test procedure

## Toolchain used

- Procursus Clang 16.0.0 (5.9.2 toolchain distribution), native arm64.
- Existing `/var/jb/usr/share/SDKs/iPhoneOS.sdk`; a second iPhoneOS 16.5 SDK and Theos installation were also found in the workspace.
- ldid 2.1.5, ld64 951.9, odcctools (`install_name_tool`, `otool`), dpkg 1.22.6, Python 3.9, make 4.4.1.
- Rootless palera1n bootstrap, `/var/jb` prefix, ElleKit 1.2, uikittools.

No missing dependencies had to be installed. No remote compiler, Apple account, signing certificate, SDK download or external runner was needed. The SDK and jailbreak libraries are supplied by the local environment and are not committed.

## Normal package

```sh
export SDK=/var/jb/usr/share/SDKs/iPhoneOS.sdk
bash build.sh
dpkg-deb -I packages/com.alsinas.sounddeck_0.1.0_iphoneos-arm64.deb
dpkg-deb -c packages/com.alsinas.sounddeck_0.1.0_iphoneos-arm64.deb
sudo dpkg -i packages/com.alsinas.sounddeck_0.1.0_iphoneos-arm64.deb
```

Every executable and the tweak receive a local ldid signature. All package payload paths are under `/var/jb`; architecture is `iphoneos-arm64`. The app is a jailbreak platform application, not an unsigned IPA intended for stock-device sideloading.

The local substrate alias advertises `/usr/local/lib/libellekit.dylib`; the build normalizes that dependency to `@rpath/libellekit.dylib` with `/var/jb/usr/lib` in the runtime search path before signing. Validate the normal package with `python3 Tools/validate-package.py packages/com.alsinas.sounddeck_0.1.0_iphoneos-arm64.deb`.

The build stages only generated files under `build/stage` and `build/test-stage`, then emits gzip Debian archives into `packages/`. It regenerates the original icon through native Core Graphics. Rebuilding from source is reproducible as a procedure; byte-for-byte artifact identity is not claimed because toolchain UUID/signature/archive metadata may vary.

## QA packages and automated tests

```sh
bash build.sh --tests
python3 Tests/run-unit.py
sudo dpkg -i packages/com.alsinas.sounddeck_0.1.0_qa_iphoneos-arm64.deb \
  packages/com.alsinas.sounddeck.tests_0.1.0_iphoneos-arm64.deb
python3 Tests/run-device.py
python3 Tests/run-ui.py
```

`--tests` enables compile-time-only scripted UI controls in the QA application and creates the separate optional signal package. It also builds a signed FrontBoard launcher because the installed `uiopen` did not reliably launch the app from this execution context. Its completion errors are checked. The normal package excludes these scripted controls.

Unit tests use an isolated preference directory, never the user's real preferences. Device tests deliberately change only the fixture bundle gains/mutes and SoundDeck's mixing/bypass settings. UI tests send real UIKit control actions, not physical touch events; the master test lowers the existing media volume then restores it. They do not modify system rotation lock or accessibility settings.

## Release-candidate recovery test

After QA, rebuild the normal package and install it. Keep the optional test package installed, then:

```sh
bash build.sh
sudo dpkg -i packages/com.alsinas.sounddeck_0.1.0_iphoneos-arm64.deb
python3 Tests/run-device.py
python3 Tests/run-lifecycle.py
```

The lifecycle harness stops only SoundDeck's service, tests the watchdog, upgrades, temporarily removes only SoundDeck while its own optional fixture package remains, and reinstalls in `finally`. It uses `dpkg --force-depends` solely for that temporary dependency on **SoundDeck's own test package**. Do not interrupt this test during the remove/reinstall interval. It does not uninstall or alter unrelated packages.

Generated local results are ignored by Git. Public reports must be copied selectively after checking for private information. Do not commit tokens, SDKs, device crash logs, browser content or package-manager credential files.
