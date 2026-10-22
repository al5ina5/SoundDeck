#!/usr/bin/env python3
import os, plistlib, sys
root=sys.argv[1]
VERSION='0.2.2'
def write(path,obj):
    os.makedirs(os.path.dirname(path),exist_ok=True)
    with open(path,'wb') as f: plistlib.dump(obj,f)
def app(name,bid,display=None):
    p=dict(CFBundleIdentifier=bid,CFBundleName=name,CFBundleDisplayName=name,CFBundleExecutable=name,
           CFBundlePackageType='APPL',CFBundleVersion='2',CFBundleShortVersionString=VERSION,
           MinimumOSVersion='15.0',LSRequiresIPhoneOS=True,UIDeviceFamily=[1,2],
           UILaunchScreen={},UIRequiredDeviceCapabilities=['arm64'],
           UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight','UIInterfaceOrientationPortraitUpsideDown'],
           CFBundleIcons={'CFBundlePrimaryIcon':{'CFBundleIconFiles':['Icon60','Icon76','Icon83.5']}})
    if name!='SoundDeck':
        p['UIBackgroundModes']=['audio']
        if display: p['CFBundleDisplayName']=display
        else: p['CFBundleDisplayName']='Signal A · 440 Hz' if name.endswith('A') else 'Signal B · 880 Hz'
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
    app('SoundDeckMediaAQ','com.alsinas.sounddeck.media.aq','AudioQueue fixture')
    app('SoundDeckMediaAVP','com.alsinas.sounddeck.media.avp','AVPlayer fixture')
    app('SoundDeckMediaAP','com.alsinas.sounddeck.media.ap','AVAudioPlayer fixture')
    app('SoundDeckMediaAE','com.alsinas.sounddeck.media.ae','AVAudioEngine fixture')
    app('SoundDeckMediaSBR','com.alsinas.sounddeck.media.sbr','Sample buffer fixture')
    app('SoundDeckWeb','com.alsinas.sounddeck.media.web','WebKit Web Audio fixture')
    app('SoundDeckWebMedia','com.alsinas.sounddeck.media.webmedia','WebKit media element fixture')
write(f'{root}/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.plist',{'Filter':{'Bundles':['com.apple.UIKit']}})
write(f'{root}/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeckWebKit.plist',{'Filter':{'Bundles':['com.apple.WebKit.WebContent','com.apple.WebKit.GPU']}})
write(f'{root}/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeckControlCenter.plist',{'Filter':{'Bundles':['com.apple.springboard']}})
write(f'{root}/var/jb/Library/ControlCenter/Bundles/SoundDeck.bundle/Info.plist',{
    'CFBundleIdentifier':'com.alsinas.sounddeck.cc','CFBundleName':'SoundDeck','CFBundleDisplayName':'SoundDeck',
    'CFBundleExecutable':'SoundDeckCC','CFBundlePackageType':'BNDL','CFBundleVersion':'2','CFBundleShortVersionString':VERSION,
    'NSPrincipalClass':'SDCCModule','MinimumOSVersion':'15.0','CFBundleSupportedPlatforms':['iPhoneOS'],'UIDeviceFamily':[1,2],
    'ModuleSize':{'columns':2,'rows':1},'CCSModuleSize':{'Portrait':{'Width':2,'Height':1},'Landscape':{'Width':2,'Height':1}}})
write(f'{root}/var/jb/Library/LaunchDaemons/com.alsinas.sounddeck.plist',{
    'Label':'com.alsinas.sounddeck','ProgramArguments':['/var/jb/usr/libexec/sounddeckd'],
    'RunAtLoad':True,'KeepAlive':True,'ProcessType':'Background','ThrottleInterval':10,
    'Umask':0o077})
write('build/tool-entitlements.plist',{'platform-application':True,'com.apple.private.security.no-container':True,
      'com.apple.private.security.no-sandbox':True})
write('build/device-entitlements.plist',{'platform-application':True,'com.apple.private.security.no-container':True,
      'com.apple.private.security.no-sandbox':True,'com.apple.frontboard.launchapplications':True,
      'com.apple.springboard.launchapplications':True})
