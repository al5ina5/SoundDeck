#!/usr/bin/env python3
"""Validate the normal release archive without executing package scripts."""
import io,pathlib,plistlib,struct,subprocess,sys,tarfile
deb=pathlib.Path(sys.argv[1]).resolve()
def output(*args): return subprocess.check_output(args)
assert output('dpkg-deb','-f',str(deb),'Architecture').decode().strip()=='iphoneos-arm64'
archive=tarfile.open(fileobj=io.BytesIO(output('dpkg-deb','--fsys-tarfile',str(deb))),mode='r:')
for member in archive:
    name=member.name.removeprefix('./').rstrip('/')
    assert name in ('','.','var','var/jb') or name.startswith('var/jb/'),f'non-rootless path: {name}'
    assert '..' not in pathlib.PurePosixPath(name).parts
    assert member.uid==0 and member.gid==0,'payload owner must be root'
root=pathlib.Path(__file__).resolve().parent.parent
destination=root/'build/validation'
destination.mkdir(parents=True,exist_ok=True)
subprocess.run(['dpkg-deb','-x',str(deb),str(destination)],check=True)
paths=['var/jb/Applications/SoundDeck.app/SoundDeck','var/jb/usr/libexec/sounddeckd','var/jb/usr/bin/sdctl','var/jb/Library/MobileSubstrate/DynamicLibraries/SoundDeck.dylib']
for path in paths:
    binary=destination/path; data=binary.read_bytes()
    magic,cpu=struct.unpack('<II',data[:8]); assert magic==0xfeedfacf and cpu==0x100000c,'must be arm64 Mach-O'
    linked=output('otool','-L',str(binary)).decode()
    assert '/usr/local/lib/' not in linked,'rootful library dependency'
    assert binary.stat().st_mode&0o111,'executable permissions missing'
app=destination/paths[0]
assert b'com.alsinas.sounddeck.test-ui.' not in app.read_bytes(),'QA hooks leaked into normal package'
entitlements=plistlib.loads(output('ldid','-e',str(app)))
assert entitlements['application-identifier']=='com.alsinas.sounddeck'
assert entitlements['platform-application']
print('PASS package architecture, rootless-only paths, owners, Mach-O, signatures/identity, dependency paths, no QA controls')
