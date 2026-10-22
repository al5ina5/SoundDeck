#!/usr/bin/env python3
"""Real-device integration tests. Does not record sound or claim human listening."""
import json, math, os, pathlib, subprocess, time, sys
from device_utils import launch_tone_ready
ROOT=pathlib.Path(__file__).resolve().parent.parent
DEVICE=str(ROOT/'build/sd-device')
A='com.alsinas.sounddeck.toneA'; B='com.alsinas.sounddeck.toneB'
results=[]
service_pid=None
def cmd(*args,check=True):
    return subprocess.run(args,check=check,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
def ctl(*args): return cmd('/var/jb/usr/bin/sdctl',*map(str,args))
def launch(bid):
    if bid in (A,B): return launch_tone_ready(DEVICE,bid)
    cmd(DEVICE,'launch',bid)
def status(): return json.loads(ctl('status').stdout)
def clients():
    data=status()
    assert time.time()-data['timestamp']<20,'stale service'
    if service_pid is not None: assert data['servicePID']==service_pid,'service restarted during test; possible crash/jetsam'
    return {c['bundleID']:c for c in data['clients']}
def settle(): time.sleep(3.2)
def verify(label,ga,gb,active=True):
    settle(); data=clients(); evidence={}
    for bid,expected in [(A,ga),(B,gb)]:
        c=data[bid]
        assert not active or c['active'],f'{bid} not rendering'
        assert c['metered'] and c['path'] in ('RemoteIO PCM','AudioUnit PCM'),f'{bid} not PCM instrumented'
        assert c['inputRMS']>.02,f'{bid} has no signal'
        ratio=c['outputRMS']/c['inputRMS']
        assert abs(ratio-expected)<.004,f'{bid}: measured {ratio}, expected {expected}'
        assert abs(c['gain']-expected)<.002,f'{bid} control state differs'
        observer=int(cmd(DEVICE,'state','com.alsinas.sounddeck.test.'+bid).stdout)
        observer_rms=(observer&0xffffffff)/65535.
        assert observer>>32,'independent post-render observer has no buffers'
        assert abs(observer_rms-(.08/math.sqrt(2))*expected)<.001,'independent post-render PCM differs from target'
        evidence[bid]={'inputRMS':c['inputRMS'],'outputRMS':c['outputRMS'],'ratio':round(ratio,6),'active':bool(c['active']),
                      'independentPostRenderRMS':observer_rms,'independentPostRenderBuffers':observer>>32}
    results.append({'test':label,'pass':True,'evidence':evidence}); print('PASS',label,flush=True)
def run():
    global service_pid
    ctl('enable'); ctl('mixing',1)
    began=time.time(); deadline=began+15
    while True:
        raw=cmd('sdctl','status',check=False)
        ready=json.loads(raw.stdout or '{}')
        if ready.get('timestamp',0)>began and ready.get('servicePID'): break
        assert time.time()<deadline,'service did not publish a new ready snapshot'
        time.sleep(.2)
    service_pid=ready['servicePID']
    cmd('killall','-9','SoundDeckToneA','SoundDeckToneB',check=False); time.sleep(.5)
    launch(A); time.sleep(2); launch(B)
    ctl('gain',A,20); ctl('gain',B,80); ctl('mute',A,0); ctl('mute',B,0)
    verify('concurrent independent 20/80 gain',.2,.8)
    for cycle in range(3):
        cmd('killall','-9','SoundDeckToneA','SoundDeckToneB',check=False); time.sleep(.5)
        launch(A); time.sleep(1); launch(B)
        verify('cold launch pair '+str(cycle+1),.2,.8)
    ctl('mute',A,1); verify('mute A leaves B unchanged',0,.8)
    ctl('mute',A,0); verify('unmute restores A',.2,.8)
    ctl('gain',A,70); verify('adjust A alone',.7,.8)
    for i in range(60):
        ctl('gain',A,(i*17)%101); ctl('mute',B,i%2)
        time.sleep(.025)
    ctl('gain',A,20); ctl('mute',B,0)
    verify('60 gain and mute cycles',.2,.8)
    oldpid=clients()[A]['pid']; cmd('kill','-KILL',str(oldpid)); deadline=time.time()+10
    while time.time()<deadline and clients().get(A,{}).get('pid')==oldpid: time.sleep(.5)
    assert clients().get(A,{}).get('pid')!=oldpid,'terminated PID remains registered after 10 seconds'
    results.append({'test':'terminated PID disappears from service','pass':True,'automaticallyRelaunched':A in clients()})
    launch(A); verify('app relaunch restores preference',.2,.8)
    launch('com.alsinas.sounddeck'); verify('both apps continue in background with mixer foreground',.2,.8)
    cmd('killall','SoundDeck'); launch('com.alsinas.sounddeck')
    verify('mixer restart preserves preferences',.2,.8)
    # bypass may allow iOS to interrupt one app after its native non-mixing category is restored.
    ctl('disable'); verify('bypass restores original unity PCM gain',1,1,active=False)
    ctl('enable')
    cmd('killall','-9','SoundDeckToneA','SoundDeckToneB',check=False); time.sleep(.5); launch(A); launch(B)
    verify('reenable and restart restores independent mix',.2,.8)
    started=time.time(); baseline=status()
    for i in range(max(1,int(os.environ.get('SD_SOAK_SECONDS','60'))//5)):
        time.sleep(5); data=clients()
        assert data[A]['active'] and data[B]['active'],'extended render stopped'
    verify('extended concurrent background playback',.2,.8)
    results[-1]['durationSeconds']=round(time.time()-started,1)
    current=status()
    results[-1]['serviceCPUPercentOneCore']=round(100*(current['serviceCpuSeconds']-baseline['serviceCpuSeconds'])/(time.time()-started),3)
    results[-1]['servicePeakRSSBytes']=current['servicePeakRSSBytes']
    launch('com.alsinas.sounddeck')
try:
    run()
except Exception as e:
    results.append({'test':'integration run','pass':False,'error':str(e)})
    print('FAIL:',e,file=sys.stderr)
finally:
    out=ROOT/'Tests/results-local'; out.mkdir(exist_ok=True)
    report={'device':'iPad7,5','os':'17.7.8 (21H440)','measurement':'injected final app RemoteIO callback PCM, not acoustic output',
            'humanListeningConfirmed':False,'results':results}
    (out/'integration.json').write_text(json.dumps(report,indent=2)+'\n')
if any(not x['pass'] for x in results): sys.exit(1)
