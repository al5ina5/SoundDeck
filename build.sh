#!/var/jb/bin/bash
set -euo pipefail
umask 022
cd "$(dirname "$0")"
SDK="${SDK:-/var/jb/usr/share/SDKs/iPhoneOS.sdk}"
LIBS="${LIBS:-/var/jb/usr/lib}"
[[ -d "$SDK" ]] || { echo "Set SDK to a local iPhoneOS SDK" >&2; exit 1; }
# Only generated staging trees owned by this build are removed.
rm -rf build/stage build/test-stage
mkdir -p build/stage/DEBIAN build/stage/var/jb/usr/{bin,libexec} build/stage/var/jb/Library/{LaunchDaemons,MobileSubstrate/DynamicLibraries} packages
python3 Tools/generate-metadata.py build/stage "$@"
CFLAGS=(-arch arm64 -mios-version-min=15.0 -isysroot "$SDK" -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations)
APPFLAGS=()
[[ " ${*:-} " == *" --tests "* ]] && APPFLAGS=(-DSD_TESTING=1)
clang "${CFLAGS[@]}" "${APPFLAGS[@]}" -framework Foundation -framework UIKit -framework CoreGraphics -framework QuartzCore -framework MediaPlayer -framework AVFoundation App/main.m App/SDMasterVolume.m Shared/SDMixerRow.m Shared/SDPreferences.m Tools/SDControlCenterConfig.m -o build/stage/var/jb/Applications/SoundDeck.app/SoundDeck
clang "${CFLAGS[@]}" -framework Foundation -lproc Backend/Service.m Shared/SDPreferences.m -o build/stage/var/jb/usr/libexec/sounddeckd
clang "${CFLAGS[@]}" -framework Foundation Tools/sdctl.m Tools/SDControlCenterConfig.m Shared/SDPreferences.m -o build/stage/var/jb/usr/bin/sdctl
clang "${CFLAGS[@]}" -bundle -framework Foundation -framework UIKit -framework CoreGraphics -framework QuartzCore -framework AVFoundation -framework MediaPlayer "${APPFLAGS[@]}" ControlCenter/SDControlCenter.m Shared/SDMixerRow.m Shared/SDPreferences.m App/SDMasterVolume.m -o build/stage/var/jb/Library/ControlCenter/Bundles/SoundDeck.bundle/SoundDeckCC
clang "${CFLAGS[@]}" "${APPFLAGS[@]}" -dynamiclib -framework Foundation -framework UIKit ControlCenter/SDBridge.m -o build/stage/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeckControlCenter.dylib
clang++ "${CFLAGS[@]}" "${APPFLAGS[@]}" -std=c++17 -dynamiclib -framework Foundation -framework AVFoundation -framework AudioToolbox -framework CoreMedia -L"$LIBS" -lsubstrate -Wl,-rpath,/var/jb/usr/lib -Wl,-install_name,@rpath/SoundDeck.dylib Backend/Runtime.mm -o build/stage/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.dylib
clang++ "${CFLAGS[@]}" "${APPFLAGS[@]}" -DSD_WEBKIT_AGENT=1 -std=c++17 -dynamiclib -framework Foundation -framework AVFoundation -framework AudioToolbox -framework CoreMedia -L"$LIBS" -lsubstrate -Wl,-rpath,/var/jb/usr/lib -Wl,-install_name,@rpath/SoundDeckWebKit.dylib Backend/Runtime.mm -o build/stage/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeckWebKit.dylib
# Procursus's substrate alias advertises a rootful install name. Normalize before signing.
install_name_tool -change /usr/local/lib/libellekit.dylib @rpath/libellekit.dylib build/stage/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.dylib
install_name_tool -change /usr/local/lib/libellekit.dylib @rpath/libellekit.dylib build/stage/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeckWebKit.dylib
if [[ "${SKIP_ICON_GEN:-0}" == "1" ]]; then
  # CI has no UIKit host runtime; reuse the icons committed in Packaging/icons.
  cp Packaging/icons/Icon*.png build/stage/var/jb/Applications/SoundDeck.app/
else
  clang "${CFLAGS[@]}" -framework UIKit -framework CoreGraphics Tools/Icon.m -o build/icon-generator
  ldid -Sbuild/tool-entitlements.plist build/icon-generator
  build/icon-generator build/stage/var/jb/Applications/SoundDeck.app
fi
cp build/stage/var/jb/Applications/SoundDeck.app/Icon60@2x.png build/stage/var/jb/Library/ControlCenter/Bundles/SoundDeck.bundle/SettingsIcon@2x.png
cp build/stage/var/jb/Applications/SoundDeck.app/Icon60@3x.png build/stage/var/jb/Library/ControlCenter/Bundles/SoundDeck.bundle/SettingsIcon@3x.png
ldid -Sbuild/SoundDeck-entitlements.plist build/stage/var/jb/Applications/SoundDeck.app/SoundDeck
ldid -Sbuild/tool-entitlements.plist build/stage/var/jb/usr/libexec/sounddeckd
ldid -Sbuild/tool-entitlements.plist build/stage/var/jb/usr/bin/sdctl
ldid -S build/stage/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.dylib
ldid -S build/stage/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeckWebKit.dylib
ldid -S build/stage/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeckControlCenter.dylib
ldid -S build/stage/var/jb/Library/ControlCenter/Bundles/SoundDeck.bundle/SoundDeckCC
if [[ " ${*:-} " == *" --tests "* ]]; then
  clang "${CFLAGS[@]}" -framework Foundation Tools/device.m -o build/sd-device
  ldid -Sbuild/device-entitlements.plist build/sd-device
  for TONE in A B; do
    FREQ=440; [[ "$TONE" == B ]] && FREQ=880
    NAME="SoundDeckTone$TONE"
    clang "${CFLAGS[@]}" -DSD_FREQUENCY="$FREQ" -framework UIKit -framework AVFoundation -framework AudioToolbox Tests/ToneApp.m -o "build/stage/var/jb/Applications/$NAME.app/$NAME"
    cp build/stage/var/jb/Applications/SoundDeck.app/Icon*.png "build/stage/var/jb/Applications/$NAME.app/"
    ldid "-Sbuild/$NAME-entitlements.plist" "build/stage/var/jb/Applications/$NAME.app/$NAME"
  done
  mkdir -p build/test-stage/var/jb/Applications build/test-stage/DEBIAN
  for MODE in 1 2 3 4 5; do
    case "$MODE" in 1) NAME=SoundDeckMediaAQ;; 2) NAME=SoundDeckMediaAVP;; 3) NAME=SoundDeckMediaAP;; 4) NAME=SoundDeckMediaAE;; 5) NAME=SoundDeckMediaSBR;; esac
    clang "${CFLAGS[@]}" -DSD_MODE="$MODE" -framework UIKit -framework AVFoundation -framework AudioToolbox -framework CoreMedia Tests/MediaApp.m -o "build/stage/var/jb/Applications/$NAME.app/$NAME"
    cp build/stage/var/jb/Applications/SoundDeck.app/Icon*.png "build/stage/var/jb/Applications/$NAME.app/"
    ldid "-Sbuild/$NAME-entitlements.plist" "build/stage/var/jb/Applications/$NAME.app/$NAME"
  done
  clang "${CFLAGS[@]}" -framework UIKit -framework WebKit -framework AVFoundation Tests/WebFixture.m -o build/stage/var/jb/Applications/SoundDeckWeb.app/SoundDeckWeb
  cp build/stage/var/jb/Applications/SoundDeck.app/Icon*.png build/stage/var/jb/Applications/SoundDeckWeb.app/
  ldid -Sbuild/SoundDeckWeb-entitlements.plist build/stage/var/jb/Applications/SoundDeckWeb.app/SoundDeckWeb
  clang "${CFLAGS[@]}" -DSD_WEB_MEDIA_ONLY=1 -framework UIKit -framework WebKit -framework AVFoundation Tests/WebFixture.m -o build/stage/var/jb/Applications/SoundDeckWebMedia.app/SoundDeckWebMedia
  cp build/stage/var/jb/Applications/SoundDeck.app/Icon*.png build/stage/var/jb/Applications/SoundDeckWebMedia.app/
  ldid -Sbuild/SoundDeckWebMedia-entitlements.plist build/stage/var/jb/Applications/SoundDeckWebMedia.app/SoundDeckWebMedia
  for NAME in SoundDeckToneA SoundDeckToneB SoundDeckMediaAQ SoundDeckMediaAVP SoundDeckMediaAP SoundDeckMediaAE SoundDeckMediaSBR SoundDeckWeb SoundDeckWebMedia; do mv "build/stage/var/jb/Applications/$NAME.app" build/test-stage/var/jb/Applications/; done
  cp Packaging/tests-control build/test-stage/DEBIAN/control
  cp Packaging/tests-postinst build/test-stage/DEBIAN/postinst
  cp Packaging/tests-prerm build/test-stage/DEBIAN/prerm
  chmod 755 build/test-stage/DEBIAN/{postinst,prerm}
  find build/test-stage -type d -exec chmod 755 {} +
  find build/test-stage -type f -name '*.png' -exec chmod 644 {} +
dpkg-deb --root-owner-group -Zgzip -b build/test-stage packages/com.alsinas.sounddeck.tests_0.2.2_iphoneos-arm64.deb
fi
cp Packaging/control Packaging/postinst Packaging/prerm Packaging/postrm build/stage/DEBIAN/
chmod 755 build/stage build/stage/DEBIAN
chmod 644 build/stage/DEBIAN/control
chmod 755 build/stage/DEBIAN/{postinst,prerm,postrm}
find build/stage/var -type d -exec chmod 755 {} +
find build/stage/var -type f -name '*.plist' -exec chmod 644 {} +
find build/stage/var -type f -name '*.png' -exec chmod 644 {} +
SUFFIX=""
[[ " ${*:-} " == *" --tests "* ]] && SUFFIX="_qa"
dpkg-deb --root-owner-group -Zgzip -b build/stage "packages/com.alsinas.sounddeck_0.2.2${SUFFIX}_iphoneos-arm64.deb"
dpkg-deb -I "packages/com.alsinas.sounddeck_0.2.2${SUFFIX}_iphoneos-arm64.deb"
