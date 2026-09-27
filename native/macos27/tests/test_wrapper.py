"""All hardware calls are replaced with a mock; tests never request real sudo."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
class WrapperTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.home=Path(self.tmp.name)
        self.helper=self.home/'native-charge'
        self.helper.write_text('#!/bin/bash\nprintf "MOCK"\nfor x in "$@"; do printf " <%s>" "$x"; done\nprintf "\\n"\n')
        self.helper.chmod(0o755)
        text=(ROOT/'src/battery-native.sh').read_text().replace(
            'ROOT=/Library/PrivilegedHelperTools/co.palokaj.battery.macos27','ROOT='+str(self.home))
        text=text.replace('if [[ $EUID -eq 0 ]]; then "$HELPER" "$@";','if true; then "$HELPER" "$@";')
        text=text.replace('if [[ $EUID -ne 0 ]]; then','if false; then')
        self.wrapper=self.home/'battery'; self.wrapper.write_text(text)
    def tearDown(self): self.tmp.cleanup()
    def call(self,*args):
        return subprocess.run(['bash',str(self.wrapper),*args],capture_output=True,text=True,timeout=5,
                              env={**os.environ,'HOME':str(self.home)})
    def test_single(self):
        r=self.call('maintain','55'); self.assertEqual(r.returncode,0); self.assertIn('<maintain> <55>',r.stdout)
        self.assertNotIn('<55> <55>',r.stdout)
    def test_single_leading_zeros(self):
        self.assertIn('<maintain> <55>',self.call('maintain','055').stdout)
    def test_stop(self): self.assertIn('<stop>',self.call('maintain','stop').stdout)
    def test_recover(self): self.assertIn('<recover>',self.call('maintain','recover').stdout)
    def test_csv(self): self.assertIn('<status_csv>',self.call('status_csv').stdout)
    def test_status(self): self.assertIn('<status>',self.call('status').stdout)
    def test_updater_probe(self):
        r=self.call('update_silent','is_enabled'); self.assertEqual(r.returncode,0); self.assertEqual(r.stdout,'')
    def test_update_paused(self):
        r=self.call('update_silent'); self.assertEqual(r.returncode,0); self.assertIn('paused',r.stdout)
    def test_reject_update_arguments(self): self.assertNotEqual(self.call('update_silent','wrong').returncode,0)
    def test_ranges_and_invalids_do_not_reach_helper(self):
        for arg in ['45-55','55-55','0','101','-50','0001','$(id)','55;id','50 60','11.5V','abc']:
            with self.subTest(arg=arg):
                r=self.call('maintain',arg); self.assertNotEqual(r.returncode,0); self.assertNotIn('MOCK',r.stdout)
    def test_unsupported_commands_do_not_reach_helper(self):
        for cmd in ['charging','adapter','charge','discharge','calibrate','cancel','maintain_voltage_synchronous']:
            with self.subTest(cmd=cmd):
                r=self.call(cmd,'on'); self.assertNotEqual(r.returncode,0); self.assertNotIn('MOCK',r.stdout)
    def test_force_discharge_not_ignored(self):
        r=self.call('maintain','55','--force-discharge'); self.assertNotEqual(r.returncode,0)
        self.assertIn('not implemented',r.stderr); self.assertNotIn('MOCK',r.stdout)
    def test_extra_args(self): self.assertNotEqual(self.call('status','oops').returncode,0)
    def test_help(self): self.assertIn('sleep',self.call().stdout)
    def test_local_version(self): self.assertIn('v1.3.4-macos27-local.0.1.4-ceiling',self.call('version').stdout)
if __name__=='__main__': unittest.main()
