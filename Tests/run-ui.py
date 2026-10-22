#!/usr/bin/env python3
"""Programmatic UIKit control-action tests on the device, not physical touch tests."""
import json,pathlib,plistlib,shutil,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parent.parent
DIR=pathlib.Path('/var/mobile/Library/SoundDeck'); OUT=ROOT/'Tests/results-local'
OUT.mkdir(exist_ok=True)
DEVICE=str(ROOT/'build/sd-device')
def cmd(*args): subprocess.run(args,check=True)
def ctl(*args): cmd('sdctl',*map(str,args))
def post(name): cmd(DEVICE,'post','com.alsinas.sounddeck.test-ui.'+name); time.sleep(3)
def capture(name):
    ctl('capture'); time.sleep(1)
    data=plistlib.load(open(DIR/'ui-diagnostics.plist','rb'))
    assert data['state']==0,'SoundDeck is not foreground active'
    assert len(data['rows'])>=2,'two active app controls not visible'
    for row in data['rows']:
        assert row['sliderAccessible'] and row['muteAccessible'] and row['iconPresent']
        assert row['touchTargetHeight']>=44 and not row['ambiguous']
    shutil.copyfile(DIR/'capture.png',OUT/(name+'.png'))
    return data
cmd(DEVICE,'launch','com.alsinas.sounddeck'); time.sleep(2)
ctl('mute','com.alsinas.sounddeck.toneA',0); ctl('mute','com.alsinas.sounddeck.toneB',0); time.sleep(3)
post('sliders')
status=json.loads(subprocess.check_output(['sdctl','status']))
for c in status['clients']:
    if c['bundleID'] not in ('com.alsinas.sounddeck.toneA','com.alsinas.sounddeck.toneB'): continue
    expected=.2 if c['bundleID'].endswith('toneA') else .8
    assert abs(c['gain']-expected)<.002,'UIKit slider did not reach real backend'
post('mute')
status=json.loads(subprocess.check_output(['sdctl','status']))
for c in status['clients']:
    if c['bundleID'] not in ('com.alsinas.sounddeck.toneA','com.alsinas.sounddeck.toneB'): continue
    assert c['gain']==(0 if c['bundleID'].endswith('toneA') else .8),'UIKit mute isolation failed'
post('unmute')
post('landscape'); ctl('appearance',1); time.sleep(2)
light=capture('landscape-light'); assert light['width']>light['height'] and light['style']==1
ctl('appearance',2); time.sleep(2)
dark=capture('landscape-dark'); assert dark['style']==2
post('portrait'); time.sleep(2)
portrait=capture('portrait-request-dark')
portrait['orientationVerified']=portrait['height']>portrait['width']
if not portrait['orientationVerified']:
    error=DIR/'rotation-test.plist'
    portrait['blockedReason']=plistlib.load(open(error,'rb'))['error'] if error.exists() else 'No geometry change observed'
post('master')
time.sleep(1.5)
master=plistlib.load(open(DIR/'master-test.plist','rb'))
assert master['initial']>0,'master was silent; no useful master test'
assert master['changed']<master['initial']-.01,'master volume did not change'
assert abs(master['initial']-master['restored'])<.025,'master volume did not restore'
assert abs(master['initial']-master['restoredNative'])<.025,'native master volume did not restore'
post('landscape'); ctl('appearance',0)
report={'uiActions':'UIKit sendActions, not human touch','sliderAndMuteToBackend':True,'light':light,'dark':dark,'portrait':portrait,'masterVolume':master}
(OUT/'ui.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS UIKit slider/mute actions, appearance, accessibility geometry, native master volume')
print('Portrait:', 'verified' if portrait['orientationVerified'] else 'BLOCKED: '+portrait['blockedReason'])
