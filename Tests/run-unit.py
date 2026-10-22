#!/usr/bin/env python3
import os,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parent.parent
out=root/'Tests/results-local/preferences-fixture'; out.mkdir(parents=True,exist_ok=True)
binary=root/'build/preferences-tests'
subprocess.run(['clang','-arch','arm64','-mios-version-min=15.0','-isysroot',os.environ.get('SDK','/var/jb/usr/share/SDKs/iPhoneOS.sdk'),
                '-fobjc-arc','-O2','-Wall','-Wextra',f'-DSD_DIR=@"{out}"','-framework','Foundation',
                str(root/'Tests/PreferencesTests.m'),str(root/'Shared/SDPreferences.m'),'-o',str(binary)],check=True)
subprocess.run(['ldid','-S'+str(root/'build/tool-entitlements.plist'),str(binary)],check=True)
subprocess.run([str(binary)],check=True)
