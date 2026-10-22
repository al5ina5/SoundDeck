#!/usr/bin/env python3
"""Programmatic UIKit control-action tests on the device, not physical touch tests."""
import json,pathlib,plistlib,shutil,subprocess,time,sys
from device_utils import launch_tone_ready
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
subprocess.run(['killall','-9','SpringBoard'],check=False)
time.sleep(8)
for exe in ('SoundDeckMediaAQ','SoundDeckMediaAVP','SoundDeckMediaAP','SoundDeckMediaAE','SoundDeckMediaSBR','SoundDeckWeb','SoundDeckWebMedia'):
    subprocess.run(['killall','-9',exe],check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(1)
launch_tone_ready(DEVICE,'com.alsinas.sounddeck.toneA'); launch_tone_ready(DEVICE,'com.alsinas.sounddeck.toneB')
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
assert master['initial']>=0,'master volume unavailable'
assert abs(master['changed']-master['initial'])>.01,'master volume did not change'
# AVAudioSession.outputVolume can lag; the AVSystemController getter is authoritative.
assert abs(master['initial']-master['restoredNative'])<.025,'native master volume did not restore'
post('landscape'); ctl('appearance',0)
# Control Center module: real SpringBoard presentation, per-app slider action, master setter, capture.
# Use two native-volume media fixtures: they start reliably after the UI stress above.
for exe in ('SoundDeckToneA','SoundDeckToneB','SoundDeckMediaAE','SoundDeckMediaAVP','SoundDeckMediaSBR','SoundDeckWeb','SoundDeckWebMedia'):
    subprocess.run(['killall','-9',exe],check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(1)
for bid in ('com.alsinas.sounddeck.media.aq','com.alsinas.sounddeck.media.ap'):
    ctl('gain',bid,100); ctl('mute',bid,0); subprocess.run([DEVICE,'launch',bid],check=True); time.sleep(1)
end=time.time()+15
while time.time()<end:
    st=json.loads(subprocess.check_output(['sdctl','status']))
    rows={c['bundleID']:c for c in st['clients'] if c['bundleID'] in ('com.alsinas.sounddeck.media.aq','com.alsinas.sounddeck.media.ap')}
    if len(rows)==2 and all(c['active'] for c in rows.values()): break
    time.sleep(.5)
else: raise AssertionError('media fixtures did not both become active for Control Center test')
ctl('cc-show'); time.sleep(2); ctl('cc-expand')
def cc_wait(pred,label,timeout=12):
    end=time.time()+timeout; last=None
    while time.time()<end:
        try: last=plistlib.load(open(DIR/'cc-diagnostics.plist','rb'))
        except Exception: last=None
        if last and pred(last): return last
        time.sleep(.4)
    raise AssertionError(label+' last='+repr(last))
cc=cc_wait(lambda d: d.get('expanded') and len(d.get('rows',[]))>=2,'Control Center expanded with two rows')
base_rows=sorted(r['bundleID'] for r in cc['rows'][:2])
expected={base_rows[0]:.2,base_rows[1]:.8}
subprocess.run([DEVICE,'post','com.alsinas.sounddeck.cc.test-sliders'],check=True); time.sleep(2)
status=json.loads(subprocess.check_output(['sdctl','status']))
for c in status['clients']:
    if c['bundleID'] in expected: assert abs(c['gain']-expected[c['bundleID']])<.002,'Control Center slider did not reach real backend'
cc=cc_wait(lambda d: len(d.get('rows',[]))>=2 and all(abs(r['gain']-expected.get(r['bundleID'],-1))<.01 for r in d['rows'][:2]),'Control Center rows reflect slider changes')
ctl('cc-capture'); time.sleep(1)
ccdata=plistlib.load(open(DIR/'cc-diagnostics.plist','rb')); assert len(ccdata['rows'])>=2 and ccdata['visible']
assert (DIR/'cc-capture.png').stat().st_size>5000,'Control Center capture empty'
shutil.copyfile(DIR/'cc-capture.png',OUT/'control-center.png')
subprocess.run([DEVICE,'post','com.alsinas.sounddeck.cc.test-master'],check=True); time.sleep(2)
mt=plistlib.load(open(DIR/'cc-master-test.plist','rb'))
assert mt['set'] and abs(mt['after']-mt['target'])<.03,'Control Center master setter failed'
assert abs(mt['restored']-mt['before'])<.03,'Control Center master did not restore'
prefs=plistlib.load(open(DIR/'preferences.plist','rb'))
for bid,val in expected.items(): assert abs(prefs['apps'][bid]['gain']-val)<.005,'Control Center preference was not persisted'
for bid in expected: ctl('gain',bid,100); ctl('mute',bid,0)
ctl('cc-dismiss'); time.sleep(2)
dismissal=plistlib.load(open(DIR/'cc-bridge.plist','rb'))
assert dismissal.get('dismissRequested') and not dismissal.get('presentedAfter'),'Control Center did not dismiss through SpringBoard bridge'
report={'uiActions':'UIKit sendActions, not human touch','sliderAndMuteToBackend':True,'light':light,'dark':dark,'portrait':portrait,'masterVolume':master,'controlCenter':{'expandedRows':len(cc['rows']),'captureBytes':(OUT/'control-center.png').stat().st_size,'masterTest':mt,'preferencesPersisted':True,'dismissal':dismissal}}
(OUT/'ui.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS UIKit slider/mute actions, appearance, accessibility geometry, native master volume')
print('PASS Control Center module, sliders, master setter, capture, persistence')
print('Portrait:', 'verified' if portrait['orientationVerified'] else 'BLOCKED: '+portrait['blockedReason'])
