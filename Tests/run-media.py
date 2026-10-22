#!/usr/bin/env python3
"""Real-device tests for the native-volume and PCM adapters beyond RemoteIO."""
import json,math,pathlib,subprocess,time,sys
ROOT=pathlib.Path(__file__).resolve().parent.parent
DEVICE=str(ROOT/'build/sd-device'); SDCTL='/var/jb/usr/bin/sdctl'
FIX={
 'aq':('com.alsinas.sounddeck.media.aq','SoundDeckMediaAQ','AudioQueue'),
 'avp':('com.alsinas.sounddeck.media.avp','SoundDeckMediaAVP','AVPlayer'),
 'ap':('com.alsinas.sounddeck.media.ap','SoundDeckMediaAP','AVAudioPlayer'),
 'ae':('com.alsinas.sounddeck.media.ae','SoundDeckMediaAE','AVAudioEngine PCM'),
 'sbr':('com.alsinas.sounddeck.media.sbr','SoundDeckMediaSBR','Sample buffer'),
}
results=[]; service_pid=None
def cmd(*args,check=True): return subprocess.run(args,check=check,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
def ctl(*args): return cmd(SDCTL,*map(str,args))
def status(): return json.loads(ctl('status').stdout)
def client(key,web=None):
    bid,_,path=FIX[key]; now=status(); assert time.time()-now['timestamp']<4,'stale service'
    if service_pid is not None: assert now['servicePID']==service_pid,'service restarted during media tests'
    rows=[c for c in now['clients'] if c['bundleID']==bid]
    if web is not None: rows=[c for c in rows if bool(c['webProcess'])==web]
    return rows[0] if rows else None
def wait(pred,label,timeout=14):
    end=time.time()+timeout; last=None
    while time.time()<end:
        last=pred()
        if last: return last
        time.sleep(.4)
    raise AssertionError(label+' (last='+json.dumps(last)+')')
def launch(key):
    _,exe,_=FIX[key]; cmd('killall','-9',exe,check=False); time.sleep(.4); cmd(DEVICE,'launch',FIX[key][0])
    return wait(lambda: (lambda c: c if c and c['active'] and c['path']==FIX[key][2] else None)(client(key)),'launch '+key)
def setgain(key,v): ctl('gain',FIX[key][0],v)
def mute(key,v): ctl('mute',FIX[key][0],v)
def reset(): ctl('enable'); ctl('mixing',1)
def check_native(key,gain,base,label):
    c=wait(lambda: (lambda c: c if c and c['active'] and abs(c['nativeBase']-base)<.006 and abs(c['nativeVolume']-base*gain)<.012 else None)(client(key)),label)
    assert c['path']==FIX[key][2] and c['controllable'],c
    results.append({'test':label,'pass':True,'bundleID':FIX[key][0],'path':c['path'],'gain':c['gain'],'nativeBase':c['nativeBase'],'nativeVolume':c['nativeVolume'],'pid':c['pid']})
    print('PASS',label,flush=True); return c
def run():
    global service_pid
    reset(); service_pid=status()['servicePID']
    for key in ('aq','avp','ap','sbr'):
        launch(key); setgain(key,40); mute(key,0)
        check_native(key,.4,.9,key+' 40% of base 0.9')
        cmd(DEVICE,'post','com.alsinas.sounddeck.test-base.'+FIX[key][0])
        check_native(key,.4,.6,key+' follows host volume change to 0.6')
        mute(key,1); c=wait(lambda: (lambda c: c if c and c['nativeVolume']==0 else None)(client(key)),key+' mute')
        assert abs(c['nativeBase']-.6)<.006
        results.append({'test':key+' mute zeroes native volume','pass':True,'nativeVolume':c['nativeVolume'],'nativeBase':c['nativeBase']})
        print('PASS',key+' mute zeroes native volume',flush=True)
        mute(key,0); setgain(key,100)
        check_native(key,1,.6,key+' unmute restores base')
    launch('ae'); setgain('ae',60); mute('ae',0)
    c=wait(lambda: (lambda c: c if c and c['active'] and c['metered'] and c['inputRMS']>.02 and abs(c['outputRMS']/c['inputRMS']-.6)<.03 else None)(client('ae')),'AVAudioEngine 60% PCM')
    obs=int(cmd(DEVICE,'state','com.alsinas.sounddeck.test.'+FIX['ae'][0]).stdout); obsrms=(obs&0xffffffff)/65535.
    assert obs>>32 and abs(obsrms-c['outputRMS'])<.006,'independent engine observer differs'
    results.append({'test':'AVAudioEngine 60% PCM','pass':True,'inputRMS':c['inputRMS'],'outputRMS':c['outputRMS'],'ratio':round(c['outputRMS']/c['inputRMS'],6),'independentPostRenderRMS':obsrms,'independentBuffers':obs>>32})
    print('PASS AVAudioEngine 60% PCM',flush=True)
    mute('ae',1)
    c=wait(lambda: (lambda c: c if c and c['active'] and c['outputRMS']==0 and c['inputRMS']>.02 else None)(client('ae')),'AVAudioEngine mute')
    print('PASS AVAudioEngine mute zeroes output',flush=True); mute('ae',0); setgain('ae',100)
    # All five adapters simultaneously.
    cmd('killall','-9','SoundDeckMediaAQ','SoundDeckMediaAVP','SoundDeckMediaAP','SoundDeckMediaAE','SoundDeckMediaSBR',check=False); time.sleep(.8)
    gains={'aq':.2,'avp':.35,'ap':.5,'ae':.65,'sbr':.8}
    for key in ('aq','avp','ap','ae','sbr'):
        cmd(DEVICE,'launch',FIX[key][0]); setgain(key,int(gains[key]*100)); mute(key,0); time.sleep(.6)
    for key in ('aq','avp','ap','sbr'):
        check_native(key,gains[key],.9,key+' simultaneous independent gain')
    c=wait(lambda: (lambda c: c if c and c['active'] and c['metered'] and c['inputRMS']>.02 and abs(c['outputRMS']/c['inputRMS']-.65)<.03 else None)(client('ae')),'AVAudioEngine simultaneous PCM')
    print('PASS AVAudioEngine simultaneous PCM',flush=True)
    pids={key:client(key)['pid'] for key in FIX if key!='ae'}
    assert len(set(pids.values()))==4,'adapters did not run in independent processes'
    # Persistence through process restart for one native adapter.
    setgain('aq',25); cmd('killall','-9','SoundDeckMediaAQ',check=False); time.sleep(.6)
    cmd(DEVICE,'launch',FIX['aq'][0]); check_native('aq',.25,.9,'AudioQueue relaunch restores preference')
    for key in ('aq','avp','ap','ae','sbr'): setgain(key,100); mute(key,0)
    results.append({'test':'five adapters run concurrently','pass':True,'pids':pids})
    print('PASS five adapters run concurrently',flush=True)
try: run()
except Exception as e:
    results.append({'test':'media integration run','pass':False,'error':str(e)}); print('FAIL:',e,file=sys.stderr)
finally:
    out=ROOT/'Tests/results-local'; out.mkdir(exist_ok=True)
    (out/'media.json').write_text(json.dumps({'device':'iPad7,5','os':'17.7.8 (21H440)','humanListeningConfirmed':False,'results':results},indent=2)+'\n')
if any(not r['pass'] for r in results): sys.exit(1)
