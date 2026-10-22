#!/usr/bin/env python3
import os, plistlib, sys
root=sys.argv[1]
def write(path,obj):
    os.makedirs(os.path.dirname(path),exist_ok=True)
    with open(path,'wb') as f: plistlib.dump(obj,f)
def app(name,bid):
    p=dict(CFBundleIdentifier=bid,CFBundleName=name,CFBundleDisplayName=name,CFBundleExecutable=name,
           CFBundlePackageType='APPL',CFBundleVersion='1',CFBundleShortVersionString='0.1.0',
           MinimumOSVersion='15.0',LSRequiresIPhoneOS=True,UIDeviceFamily=[1,2],
           UILaunchScreen={},UIRequiredDeviceCapabilities=['arm64'],
           UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight','UIInterfaceOrientationPortraitUpsideDown'],
           CFBundleIcons={'CFBundlePrimaryIcon':{'CFBundleIconFiles':['Icon60','Icon76','Icon83.5']}})
    if name!='SoundDeck':
        p['UIBackgroundModes']=['audio']
        p['CFBundleDisplayName']='Signal A · 440 Hz' if name.endswith('A') else 'Signal B · 880 Hz'
    else:
        p['UIApplicationSceneManifest']={'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{
            'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default Configuration','UISceneDelegateClassName':'SDSceneDelegate'}]}}
    write(f'{root}/var/jb/Applications/{name}.app/Info.plist',p)
    write(f'build/{name}-entitlements.plist',{'application-identifier':bid,'platform-application':True,
          'com.apple.private.security.no-container':True,'com.apple.private.security.no-sandbox':True})
app('SoundDeck','com.alsinas.sounddeck')
if '--tests' in sys.argv:
    app('SoundDeckToneA','com.alsinas.sounddeck.toneA')
    app('SoundDeckToneB','com.alsinas.sounddeck.toneB')
write(f'{root}/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.plist',{'Filter':{'Bundles':['com.alsinas.sounddeck.toneA','com.alsinas.sounddeck.toneB']}})
write(f'{root}/var/jb/Library/LaunchDaemons/com.alsinas.sounddeck.plist',{
    'Label':'com.alsinas.sounddeck','ProgramArguments':['/var/jb/usr/libexec/sounddeckd'],
    'RunAtLoad':True,'KeepAlive':True,'ProcessType':'Background','ThrottleInterval':10,
    'Umask':0o077})
write('build/tool-entitlements.plist',{'platform-application':True,'com.apple.private.security.no-container':True,
      'com.apple.private.security.no-sandbox':True})
write('build/device-entitlements.plist',{'platform-application':True,'com.apple.private.security.no-container':True,
      'com.apple.private.security.no-sandbox':True,'com.apple.frontboard.launchapplications':True,
      'com.apple.springboard.launchapplications':True})
