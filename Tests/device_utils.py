import subprocess,time

def launch_tone_ready(device,bundle_id):
    """Foreground until this NEW process has really rendered; FrontBoard OK is not audio-ready."""
    session_name='com.alsinas.sounddeck.session.'+bundle_id
    meter_name='com.alsinas.sounddeck.test.'+bundle_id
    def state(name): return int(subprocess.check_output([device,'state',name]))
    previous_pid=state(session_name)>>32
    subprocess.run([device,'launch',bundle_id],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    deadline=time.time()+20
    while time.time()<deadline:
        pid=state(session_name)>>32
        buffers=state(meter_name)>>32
        if pid and pid!=previous_pid and buffers>0: return pid
        time.sleep(.2)
    raise AssertionError(bundle_id+': new process did not report real post-render buffers while foreground within 20s')
