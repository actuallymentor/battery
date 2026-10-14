"""Isolated firmware tests. No system SMC, sudo, launchctl or installed CLI calls."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]

SMC = r'''#!/usr/bin/python3
import json, pathlib, sys
folder=pathlib.Path(__file__).parent
p=folder/'smc.json'
s=json.loads(p.read_text()); args=sys.argv[1:]; key=args[1]
if args[2]=='-r':
    if s.get('read_error')==key:
        print('Error: no data'); sys.exit(0)
    if key not in s['keys']:
        print('no data'); sys.exit(0)
    value=s['keys'][key]
    typ='ui8 ' if key=='bfF0' else 'hex_' if key=='CHIE' else 'ui32'
    print('  '+key+'  ['+typ+']  (bytes '+' '.join(value[i:i+2] for i in range(0,len(value),2))+')')
else:
    value=args[3]
    if s.get('fail')==[key,value]:
        print('Error: rejected'); sys.exit(0)
    s['keys'][key]=value
    s.setdefault('writes',[]).append([key,value])
    p.write_text(json.dumps(s))
'''

class FirmwareTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='battery-fixture-')
        self.folder = Path(self.temp.name)
        self.smc = self.folder/'smc'
        self.smc.write_text(SMC); self.smc.chmod(0o755)
        self.state = self.folder/'smc.json'
        self.state.write_text(json.dumps({'keys': {'bfF0':'00','bfD0':'00000000','bfE0':'00000000','CHIE':'00'}, 'writes':[]}))
        self.battery = self.folder/'battery'
        self.prelude = '\n'.join([
            'configfolder='+shlex.quote(str(self.folder)),
            'smc_binary='+shlex.quote(str(self.smc)),
            'battery_binary='+shlex.quote(str(self.battery)),
            'pidfile="$configfolder/battery.pid"',
            'logfile="$configfolder/battery.log"',
            'maintain_percentage_tracker_file="$configfolder/maintain.percentage"',
            'sudo() { [[ "$1" != -n ]] || shift; "$@"; }',
            'get_battery_percentage() { echo 95; }',
            'source '+shlex.quote(str(ROOT/'firmware.sh')),
            'fw_period=0.1',
            'fw_telemetry() { fw_percent=95; fw_current=1000; fw_raw=5000; fw_max=6000; fw_external=true; fw_charging=true; fw_input=30000; fw_load=17000; fw_battery_power=13000; if [[ -f "$configfolder/telemetry" ]]; then read -r fw_percent fw_current fw_raw fw_max fw_external fw_charging fw_input fw_load fw_battery_power < "$configfolder/telemetry"; fi; fw_stamp=$(date +%s); }',
        ])
        self.battery.write_text('#!/bin/bash\n'+self.prelude+'''
case "$1" in
 firmware_synchronous) [[ ! -f "$configfolder/fail-worker" ]] || exit 1; fw_worker "$2" ;;
 maintain) fw_request "$2" "$3" ;;
 create_daemon|disable_daemon) echo "$1" > "$configfolder/daemon-state" ;;
esac
''')
        self.battery.chmod(0o755)

    def tearDown(self):
        p = self.folder/'battery.pid'
        if p.exists():
            try: os.kill(int(p.read_text()),15)
            except (ProcessLookupError, ValueError): pass
        time.sleep(.15)
        self.temp.cleanup()

    def run_shell(self, code):
        return subprocess.run(['/bin/bash','-c',self.prelude+'\n'+code],capture_output=True,text=True,timeout=20)

    def request(self,target,option=''):
        return subprocess.run(['/bin/bash',str(self.battery),'maintain',str(target),option],capture_output=True,text=True,timeout=20)

    def test_decimal_contract(self):
        for value,wanted in [('060','60'),('08','8'),('0','0'),('96','96'),('100','100')]:
            r=self.run_shell('fw_decimal '+shlex.quote(value))
            self.assertEqual((r.returncode,r.stdout.strip()),(0,wanted),r.stderr)
        for value in ['-1','101','1.5','','1; echo bad','999999999999999999999999999']:
            self.assertNotEqual(self.run_shell('fw_decimal '+shlex.quote(value)).returncode,0)

    def test_actual_encoding_and_dynamic_target(self):
        for target,upper,lower in [(60,'3c000000','3a000000'),(75,'4b000000','49000000'),(96,'60000000','5e000000'),(1,'01000000','00000000')]:
            r=self.run_shell('fw_apply '+str(target))
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertEqual(json.loads(self.state.read_text())['keys'],{'bfF0':'02','bfD0':upper,'bfE0':lower,'CHIE':'00'})

    def test_zero_exit_smc_error_is_failure_and_rollback(self):
        s=json.loads(self.state.read_text()); s['fail']=['bfE0','3a000000']; self.state.write_text(json.dumps(s))
        r=self.run_shell('fw_snapshot && { fw_apply 60; rc=$?; fw_restore; exit "$rc"; }')
        self.assertNotEqual(r.returncode,0)
        self.assertEqual(json.loads(self.state.read_text())['keys'],s['keys'])

    def test_invalid_request_preserves_hardware_and_policy(self):
        self.assertEqual(self.request(60).returncode,0)
        policy=(self.folder/'firmware.policy').read_text()
        before=json.loads(self.state.read_text())['keys']
        for bad in ['0','abc','101','58-60','11.4V','08x']:
            self.assertNotEqual(self.request(bad).returncode,0)
            self.assertEqual((self.folder/'firmware.policy').read_text(),policy)
            self.assertEqual(json.loads(self.state.read_text())['keys'],before)

    def test_apply_change_stop_recover_and_full_charge(self):
        for target in [60,75,96]:
            r=self.request(target); self.assertEqual(r.returncode,0,r.stderr)
            self.assertEqual((self.folder/'maintain.percentage').read_text().strip(),str(target))
            self.assertEqual(json.loads(self.state.read_text())['keys']['bfD0'],f'{target:02x}000000')
        r=self.request('stop'); self.assertEqual(r.returncode,0,r.stderr)
        before=self.state.read_text()
        self.assertEqual(self.request('recover').returncode,0)
        self.assertEqual(self.state.read_text(),before)
        self.assertTrue((self.folder/'firmware.policy').read_text().startswith('stopped 96 '))
        r=self.request(100); self.assertEqual(r.returncode,0,r.stderr)
        self.assertTrue((self.folder/'firmware.policy').read_text().startswith('unlimited 100 '))
        self.assertEqual(json.loads(self.state.read_text())['keys']['bfF0'],'00')

    def test_failed_worker_restores_previous_target_and_controller(self):
        self.assertEqual(self.request(60).returncode,0)
        old_pid=(self.folder/'battery.pid').read_text()
        old_policy=(self.folder/'firmware.policy').read_text()
        (self.folder/'fail-worker').touch()
        r=self.request(75); self.assertNotEqual(r.returncode,0)
        self.assertEqual((self.folder/'firmware.policy').read_text(),old_policy)
        self.assertEqual((self.folder/'battery.pid').read_text(),old_pid)
        self.assertEqual(json.loads(self.state.read_text())['keys']['bfD0'],'3c000000')
        os.kill(int(old_pid),0)

    def test_repeated_same_target_does_not_cycle_limit(self):
        self.assertEqual(self.request(60).returncode,0)
        old=json.loads(self.state.read_text())['writes']
        self.assertEqual(self.request(60).returncode,0)
        self.assertEqual(json.loads(self.state.read_text())['writes'],old)

    def test_unowned_active_policy_is_not_overwritten(self):
        self.run_shell('fw_apply 75')
        before=self.state.read_text()
        self.assertNotEqual(self.request(60).returncode,0)
        self.assertEqual(self.state.read_text(),before)

    def test_stale_or_repeated_sensor_does_not_prove_bypass(self):
        setup='fw_reset_window; fw_reached=true; fw_percent=96; fw_current=0; fw_raw=5889; fw_max=6198; fw_external=true; fw_charging=false; fw_input=20000; fw_load=20000; fw_battery_power=0;'
        r=self.run_shell(setup+'fw_stamp=1000; for now in 1000 1030 1060 1090 1120 1150 1300; do fw_observe "$now" 96; done; echo "$fw_power"')
        self.assertEqual(r.stdout.strip(),'unknown',r.stderr)
        r=self.run_shell(setup+'for now in 1000 1060 1120 1180 1240 1300; do fw_stamp=$now; fw_observe "$now" 96; done; echo "$fw_power"')
        self.assertEqual(r.stdout.strip(),'bypass_verified',r.stderr)

    def test_not_charging_alone_is_not_bypass(self):
        for overrides in ['fw_current=-1000','fw_raw=$((fw_raw+5))','fw_input=0','fw_external=false','fw_battery_power=5000','fw_reached=false']:
            r=self.run_shell('fw_reset_window; fw_reached=true; fw_percent=96; fw_current=0; fw_raw=5889; fw_max=6198; fw_external=true; fw_charging=false; fw_input=20000; fw_load=20000; fw_battery_power=0; for now in 1000 1060 1120 1180 1240 1300; do fw_stamp=$now; '+overrides+'; fw_observe "$now" 96; done; echo "$fw_power"')
            self.assertNotEqual(r.stdout.strip(),'bypass_verified',overrides)

    def wait_key(self,key,wanted):
        deadline=time.time()+5
        while time.time()<deadline:
            if json.loads(self.state.read_text())['keys'][key]==wanted: return
            time.sleep(.1)
        self.fail(f'{key} did not become {wanted}')

    def test_initial_force_discharge_restores_adapter_at_target(self):
        r=self.request(60,'--force-discharge'); self.assertEqual(r.returncode,0,r.stderr)
        self.wait_key('CHIE','08')
        (self.folder/'telemetry').write_text('60 -1000 3600 6000 false false 700 13700 -13000\n')
        self.wait_key('CHIE','00')
        self.assertEqual(json.loads(self.state.read_text())['keys']['bfF0'],'02')
        self.assertEqual(json.loads(self.state.read_text())['keys']['bfD0'],'3c000000')
        deadline=time.time()+5
        while time.time()<deadline and 'event=initial_phase_complete' not in (self.folder/'battery.log').read_text(): time.sleep(.05)
        self.assertIn('event=initial_phase_complete',(self.folder/'battery.log').read_text())

    def test_force_flag_does_not_discharge_when_below_target(self):
        r=self.request(96,'--force-discharge'); self.assertEqual(r.returncode,0,r.stderr)
        time.sleep(.3)
        self.assertNotIn(['CHIE','08'],json.loads(self.state.read_text())['writes'])

    def test_competing_requests_leave_one_live_controller(self):
        first=subprocess.Popen(['/bin/bash',str(self.battery),'maintain','60',''],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        second=subprocess.Popen(['/bin/bash',str(self.battery),'maintain','75',''],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        first.communicate(timeout=20); second.communicate(timeout=20)
        self.assertEqual(first.returncode,0); self.assertEqual(second.returncode,0)
        target=int((self.folder/'maintain.percentage').read_text())
        self.assertIn(target,[60,75])
        self.assertEqual(json.loads(self.state.read_text())['keys']['bfD0'],f'{target:02x}000000')
        time.sleep(.3)
        commands=subprocess.check_output(['/bin/ps','-axo','command='],text=True).splitlines()
        self.assertEqual(sum(x.startswith('/bin/bash '+str(self.battery)+' firmware_synchronous ') for x in commands),1)
        os.kill(int((self.folder/'battery.pid').read_text()),0)

    def test_worker_exit_releases_its_initial_adapter_cut(self):
        r=self.request(60,'--force-discharge'); self.assertEqual(r.returncode,0,r.stderr)
        self.wait_key('CHIE','08')
        # Removing the PID makes the worker return normally, after its function
        # locals have gone out of scope. Cleanup must still know its generation.
        (self.folder/'battery.pid').unlink()
        self.wait_key('CHIE','00')
        self.assertEqual(json.loads(self.state.read_text())['keys']['bfF0'],'02')

    def test_status_invalidates_cached_bypass_when_adapter_was_cut(self):
        self.run_shell('fw_apply 96; fw_write CHIE 08')
        now=int(time.time())
        (self.folder/'firmware.policy').write_text('enabled 96 0 1000-1\n')
        (self.folder/'firmware.status').write_text(f'1000-1 {now} verified bypass_verified 96 0 {now}\n')
        r=self.run_shell('fw_pid_is_controller() { return 0; }; fw_telemetry() { fw_percent=96; fw_current=0; fw_stamp=$(date +%s); fw_external=true; fw_charging=false; fw_input=20000; fw_battery_power=0; }; fw_status_json')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(json.loads(r.stdout)['power'],'unknown')

if __name__=='__main__': unittest.main(verbosity=2)
