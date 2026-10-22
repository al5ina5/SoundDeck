#!/usr/bin/env python3
"""Scoped service/package recovery tests. Always reinstalls SoundDeck in finally."""
import json,pathlib,subprocess,time,math
from device_utils import launch_tone_ready
ROOT=pathlib.Path(__file__).resolve().parent.parent
DEVICE=str(ROOT/'build/sd-device'); DEB=str(ROOT/'packages/com.alsinas.sounddeck_0.1.0_iphoneos-arm64.deb')
A='com.alsinas.sounddeck.toneA'; B='com.alsinas.sounddeck.toneB'; results=[]
SERVICE='/var/jb/Library/LaunchDaemons/com.alsinas.sounddeck.plist'
def cmd(*args,check=True): return subprocess.run(args,check=check,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
def state(name): return int(cmd(DEVICE,'state',name).stdout)
def ctl(*args): return cmd('sdctl',*map(str,args))
def launch(bid):
    if bid in (A,B): return launch_tone_ready(DEVICE,bid)
    cmd(DEVICE,'launch',bid)
def restart():
    ctl('enable'); ctl('mixing',1); time.sleep(1)
    cmd('killall','-9','SoundDeckToneA','SoundDeckToneB',check=False); time.sleep(.5); launch(A); launch(B); time.sleep(4)
def unity(bid):
    value=state('com.alsinas.sounddeck.test.'+bid)
    assert value>>32,'no observed PCM'
    rms=(value&0xffffffff)/65535.
    assert abs(rms-.08/math.sqrt(2))<.001,f'not unity: {rms}'
    return rms
try:
    assert pathlib.Path(DEB).exists(),'build normal release package first'
    restart()
    for bid in (A,B): assert state('com.alsinas.sounddeck.session.'+bid)&1,'mix option missing'
    cmd('sudo','-n','launchctl','bootout','system/com.alsinas.sounddeck'); time.sleep(8)
    observed=unity(B)
    results.append({'test':'service-loss watchdog restores PCM unity','pass':True,'rms':observed})
    cmd('sudo','-n','launchctl','bootstrap','system',SERVICE); time.sleep(2); restart()
    cmd('sudo','-n','dpkg','-i',DEB); time.sleep(2)
    assert cmd('sdctl','is-disabled',check=False).returncode==1,'upgrade unexpectedly disabled user preferences'
    restart()
    data=json.loads(ctl('status').stdout)
    for c in data['clients']:
        if c['bundleID'] in (A,B): assert abs(c['gain']-(.2 if c['bundleID']==A else .8))<.002
    results.append({'test':'package upgrade preserves enabled state and gains','pass':True})
    # Only our optional fixture package temporarily depends on the removed package.
    cmd('sudo','-n','dpkg','--force-depends','-r','com.alsinas.sounddeck'); time.sleep(3)
    assert not pathlib.Path('/var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.dylib').exists()
    cmd('killall','-9','SoundDeckToneA','SoundDeckToneB',check=False); time.sleep(.5)
    launch(A); time.sleep(2); launch(B); time.sleep(4)
    for bid in (A,B): assert not (state('com.alsinas.sounddeck.session.'+bid)&1),'native nonmixing options not restored'
    observed=unity(B)
    before=state('com.alsinas.sounddeck.test.'+A)>>32; time.sleep(2)
    after=state('com.alsinas.sounddeck.test.'+A)>>32
    assert before==after,'nonmixing app A should be interrupted by native app B'
    results.append({'test':'uninstall restores native nonmixing playback and unity PCM','pass':True,'rms':observed})
except Exception as e:
    results.append({'test':'lifecycle run','pass':False,'error':str(e)})
    raise
finally:
    cmd('sudo','-n','dpkg','-i',DEB)
    time.sleep(2); restart(); launch('com.alsinas.sounddeck')
    out=ROOT/'Tests/results-local'; out.mkdir(exist_ok=True)
    (out/'lifecycle.json').write_text(json.dumps({'results':results},indent=2)+'\n')
print('PASS service watchdog, package upgrade, uninstall/native recovery, reinstall')
