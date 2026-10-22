#!/usr/bin/env python3
"""Real-device tests for WebKit subprocess attribution and gain (Web Audio + media element)."""
import json,pathlib,subprocess,time,sys
ROOT=pathlib.Path(__file__).resolve().parent.parent
DEVICE=str(ROOT/'build/sd-device'); SDCTL='/var/jb/usr/bin/sdctl'
APPS={
 'webaudio':('com.alsinas.sounddeck.media.web','SoundDeckWeb','AudioUnit PCM'),
 'media':('com.alsinas.sounddeck.media.webmedia','SoundDeckWebMedia','AVPlayer'),
}
results=[]; service_pid=None
def cmd(*args,check=True): return subprocess.run(args,check=check,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
def ctl(*args): return cmd(SDCTL,*map(str,args))
def status(): return json.loads(ctl('status').stdout)
def webclient(bid):
    now=status(); assert time.time()-now['timestamp']<max(8,now.get('discoveryDurationMs',0)/1000+4),'stale service'
    if service_pid is not None: assert now['servicePID']==service_pid,'service restarted during web tests'
    rows=[c for c in now['clients'] if c['bundleID']==bid and c['webProcess']]
    return rows[0] if rows else None
def wait(pred,label,timeout=20):
    end=time.time()+timeout; last=None
    while time.time()<end:
        try: last=pred()
        except Exception as e: last=str(e)
        if last: return last
        time.sleep(.5)
    raise AssertionError(label+' (last='+str(last)+')')
def run():
    global service_pid
    ctl('enable'); ctl('mixing',1); service_pid=status()['servicePID']
    for key,(bid,exe,expected) in APPS.items():
        cmd('killall','-9',exe,check=False); cmd('killall','-9','com.apple.WebKit.WebContent','com.apple.WebKit.GPU','com.apple.WebKit.Networking',check=False); time.sleep(1)
        cmd(DEVICE,'launch',bid)
        c=wait(lambda: (lambda c: c if c and c['active'] and c['controllable'] and c['ownerVerified'] and c['path']==expected else None)(webclient(bid)),key+' web process attribution')
        assert c['webProcess'] and c['controllable'],c
        assert [x for x in status()['clients'] if x['webProcess'] and not x['ownerVerified']]==[],'unattributed web process present'
        ctl('gain',bid,35); ctl('mute',bid,0)
        if expected=='AudioUnit PCM':
            c=wait(lambda: (lambda c: c if c and c['active'] and c['inputRMS']>.02 and abs(c['outputRMS']/c['inputRMS']-.35)<.03 else None)(webclient(bid)),key+' PCM gain')
            ratio=c['outputRMS']/c['inputRMS']
            results.append({'test':key+' Web Audio PCM 35%','pass':True,'bundleID':bid,'webPID':c['pid'],'path':c['path'],'inputRMS':c['inputRMS'],'outputRMS':c['outputRMS'],'ratio':round(ratio,6)})
            print('PASS',key,'Web Audio PCM 35%',flush=True)
            ctl('mute',bid,1)
            c=wait(lambda: (lambda c: c if c and c['active'] and c['outputRMS']==0 and c['inputRMS']>.02 else None)(webclient(bid)),key+' PCM mute')
            print('PASS',key,'Web Audio mute zeroes output',flush=True)
        else:
            c=wait(lambda: (lambda c: c if c and c['active'] and abs(c['nativeVolume']-.35)<.02 and abs(c['nativeBase']-1)<.02 else None)(webclient(bid)),key+' AVPlayer gain')
            results.append({'test':key+' media element AVPlayer 35%','pass':True,'bundleID':bid,'webPID':c['pid'],'path':c['path'],'nativeBase':c['nativeBase'],'nativeVolume':c['nativeVolume']})
            print('PASS',key,'media element AVPlayer 35%',flush=True)
            ctl('mute',bid,1)
            c=wait(lambda: (lambda c: c if c and c['active'] and c['nativeVolume']==0 else None)(webclient(bid)),key+' AVPlayer mute')
            print('PASS',key,'media element mute zeroes volume',flush=True)
        ctl('mute',bid,0); ctl('gain',bid,100)
    results.append({'test':'WebKit owner stays attributed to the host app','pass':True})
    print('PASS WebKit owner stays attributed to the host app',flush=True)
try: run()
except Exception as e:
    results.append({'test':'web integration run','pass':False,'error':str(e)}); print('FAIL:',e,file=sys.stderr)
finally:
    out=ROOT/'Tests/results-local'; out.mkdir(exist_ok=True)
    (out/'web.json').write_text(json.dumps({'device':'iPad7,5','os':'17.7.8 (21H440)','humanListeningConfirmed':False,'results':results},indent=2)+'\n')
if any(not r['pass'] for r in results): sys.exit(1)
