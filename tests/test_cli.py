"""Exercise the actual CLI dispatcher with fixed paths rewritten into a fixture."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import time
import unittest
import test_firmware as fixture

@unittest.skipIf(os.geteuid()==0, 'CLI intentionally refuses maintenance as root')
class CLITests(unittest.TestCase):
    request=fixture.FirmwareTests.request
    tearDown=fixture.FirmwareTests.tearDown
    def setUp(self):
        fixture.FirmwareTests.setUp(self)
        (self.folder/'firmware.sh').write_text((fixture.ROOT/'firmware.sh').read_text())
        main=(fixture.ROOT/'battery.sh').read_text()
        main=main.replace('configfolder=$HOME/.battery','configfolder='+shlex.quote(str(self.folder)))
        main=main.replace('binfolder="/usr/local/co.palokaj.battery"','binfolder='+shlex.quote(str(self.folder)))
        main=main.replace('daemon_path=$HOME/Library/LaunchAgents/battery.plist','daemon_path='+shlex.quote(str(self.folder/'agent.plist')))
        override='\n'.join(x for x in self.prelude.splitlines() if x.startswith('fw_telemetry()'))
        main=main.replace('source "$firmware_module"','source "$firmware_module"\nfw_period=0.1\n'+override+'\nget_battery_percentage() { echo 95; }')
        # Only the test copy fakes ownership and sudo. All write commands are
        # restricted to the fixture's mock SMC; no production test-mode switch.
        header='''#!/bin/bash
stat() {
 case "$1 $2" in '-f %u') echo 0 ;; '-f %Lp') echo 755 ;; *) /usr/bin/stat "$@" ;; esac
}
launchctl() { return 0; }
sudo() {
 [[ "$1" != -n ]] || shift
 [[ "$1" == MOCK_SMC ]] || { echo 'Forbidden test sudo command' >&2; return 99; }
 "$@"
}
'''.replace('MOCK_SMC',shlex.quote(str(self.smc)))
        self.battery.write_text(header+main)

    def cli(self,*args):
        return subprocess.run(['/bin/bash',str(self.battery),*args],capture_output=True,text=True,timeout=25)

    def test_dispatch_applies_then_reports_saved_input(self):
        r=self.cli('maintain','060'); self.assertEqual(r.returncode,0,r.stderr)
        r=self.cli('status_json'); self.assertEqual(r.returncode,0,r.stderr)
        s=json.loads(r.stdout)
        self.assertEqual(s['target'],60)
        self.assertEqual(s['lower'],58)
        self.assertEqual(s['mode'],'enabled')
        self.assertEqual(s['force_discharge'],False)

    def test_unsupported_commands_preserve_active_limit(self):
        self.assertEqual(self.cli('maintain','60').returncode,0)
        before=json.loads(self.state.read_text())['keys']
        policy=(self.folder/'firmware.policy').read_text()
        for args in [('maintain','58-60'),('maintain','60','--bad'),('maintain','60','','extra'),('charge','100'),('adapter','off'),('calibrate',)]:
            r=self.cli(*args); self.assertNotEqual(r.returncode,0,(args,r.stderr))
            self.assertEqual(json.loads(self.state.read_text())['keys'],before)
            self.assertEqual((self.folder/'firmware.policy').read_text(),policy)

    def test_startup_recover_preserves_explicit_stop(self):
        self.assertEqual(self.cli('maintain','60').returncode,0)
        self.assertEqual(self.cli('maintain','stop').returncode,0)
        self.assertEqual(self.cli('maintain','recover').returncode,0)
        self.assertEqual(json.loads(self.cli('status_json').stdout)['mode'],'stopped')
        self.assertEqual(json.loads(self.state.read_text())['keys']['bfF0'],'00')

    def test_local_update_cannot_replace_controller(self):
        before=self.battery.read_bytes()
        self.assertEqual(self.cli('update_silent').returncode,0)
        self.assertNotEqual(self.cli('update').returncode,0)
        self.assertNotEqual(self.cli('reinstall').returncode,0)
        self.assertEqual(self.battery.read_bytes(),before)

    def test_login_recovery_does_not_pause_its_own_subshell(self):
        (self.folder/'firmware.policy').write_text('enabled 60 0 1000-1\n')
        (self.folder/'maintain.percentage').write_text('60\n')
        r=self.cli('maintain_synchronous','recover')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(json.loads(self.state.read_text())['keys']['bfD0'],'3c000000')
        os.kill(int((self.folder/'battery.pid').read_text()),0)

if __name__=='__main__': unittest.main(verbosity=2)
