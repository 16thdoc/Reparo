#!/usr/bin/env sh
# Registry tests never connect to the production reporting endpoint.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sh -n "$repo/linux/reparo-linux"
sh -n "$repo/deploy/install-reparo-linux.sh"
python3 - "$repo" <<'TEST_PY'
import copy, datetime, hashlib, json, os, pathlib, stat, subprocess, sys, tempfile, time, types, unittest, uuid
repo=pathlib.Path(sys.argv[1])
source=(repo/'linux/reparo-linux').read_text()
code=source.split("<<'REPARO_REGISTRY_PY'",1)[1].split('\n',1)[1].split('\nREPARO_REGISTRY_PY\n',1)[0]
code=code.split('try: main(sys.argv[1:])',1)[0]
module={'__name__':'registry_test'}
exec(compile(code,'embedded-reparo-registry','exec'),module)

class RegistryTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='reparo-registry-test-')
        self.root=pathlib.Path(self.tmp.name)
        self.state=self.root/'state'/'registry'
        self.runtime=self.root/'reparo-linux'
        self.runtime.write_text("REPARO_LINUX_VERSION='1.2.3.4'\n")
        self.sent=[];self.accept=False
        self.original_collect=module['collect_facts'];self.original_send=module['send_event'];self.original_bounded=module['bounded_command']
        def collect(installed,executing,version,state,queued):
            # Synthetic facts only; real collection tested separately without HTTP.
            return {'machine_name':'fixture-device','fqdn':'fixture-device.example.invalid','organization':None,'site':None,'asset_label':None,
                'first_install_at':state['first_install_at'],'first_install_source':'recorded-install' if state['first_install_at'] else None,
                'installed_version':'1.2.3.4','executed_version':version,'source_sha256':hashlib.sha256(self.runtime.read_bytes()).hexdigest().upper(),
                'source_commit':state['source_commit'],'os_family':'linux','os_edition':'Fixture Linux','os_version':'1','os_build':'fixture',
                'architecture':'x64','domain_joined':None,'domain_name':None,'workgroup':None,'entra_joined':None,'last_boot_at':None,'uptime_seconds':None,
                'pending_reboot':None,'schedule':{'supported':False,'enabled':None,'next_due':None,'last_result':None},
                'reporting':{'identity_scope':'native-user','status':'ready','queued':queued,'retry_count':state['retry_count'],'last_success_at':state['last_success_at']},
                'volume':{'free_bytes':None,'total_bytes':None},'package_managers':[]}
        def send(secret,event,timeout):
            self.assertRegex(secret,'^[0-9a-f]{64}$');self.assertGreater(timeout,0);self.assertLessEqual(timeout,2.0)
            self.sent.append(copy.deepcopy(event));return self.accept
        module['collect_facts']=collect;module['send_event']=send
    def tearDown(self):
        module['collect_facts']=self.original_collect;module['send_event']=self.original_send;module['bounded_command']=self.original_bounded
        self.tmp.cleanup()
    def run_report(self,kind='run',outcome='started',fresh='0',commit='',previous='',source='',duration='',failure='',receipts='',capture_health='complete'):
        module['main']([str(self.state),str(self.runtime),str(self.runtime),'1.2.3.4',kind,outcome,previous,source,duration,failure,fresh,commit,receipts,capture_health])
    def load(self,name): return json.loads((self.state/name).read_text())
    def test_automatic_identity_private_retry_and_idempotent_event(self):
        self.run_report()
        identity=self.load('identity.json');event=self.load('queue.json')[0]
        self.assertEqual(event['event_type'],'run');self.assertEqual(event['facts']['first_install_at'],None)
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode),0o700)
        for name in ('identity.json','queue.json','state.lock'): self.assertEqual(stat.S_IMODE((self.state/name).stat().st_mode),0o600)
        self.accept=True;self.run_report()
        self.assertEqual(self.sent[0]['event_id'],self.sent[1]['event_id'])
        self.assertEqual(self.load('identity.json')['installation_id'],identity['installation_id'])
        self.assertEqual(self.load('identity.json')['secret'],identity['secret'])
        self.assertEqual(self.load('queue.json'),[])
        self.assertIsNotNone(self.load('identity.json')['last_success_at'])
    def test_only_successful_fresh_install_sets_first_date_once(self):
        self.run_report('install','failed','1');self.assertIsNone(self.load('identity.json')['first_install_at'])
        self.run_report('install','succeeded','1','a'*40,source='mirror',duration='2000')
        identity=self.load('identity.json');first=identity['first_install_at'];self.assertIsNotNone(first)
        event=self.load('queue.json')[-1]
        self.assertEqual(event['facts']['first_install_source'],'recorded-install')
        self.assertEqual(event['operation']['source'],'mirror');self.assertEqual(event['operation']['duration_ms'],2000)
        self.run_report('update','succeeded','0','b'*40,previous='1.2.3.3',source='github-fallback')
        self.assertEqual(self.load('identity.json')['first_install_at'],first)
        self.assertEqual(self.load('identity.json')['installation_id'],identity['installation_id'])
    def test_existing_install_unknown_is_not_backdated(self):
        self.run_report('update','succeeded','0','a'*40)
        self.assertIsNone(self.load('identity.json')['first_install_at'])
        self.assertIsNone(self.load('queue.json')[-1]['facts']['first_install_source'])
    def test_queue_bounded_and_expired_entries_removed(self):
        for i in range(15): self.run_report()
        queue=self.load('queue.json');self.assertEqual(len(queue),8)
        self.assertLessEqual((self.state/'queue.json').stat().st_size,module['MAX_QUEUE_BYTES'])
        queue[0]['client_time']='2000-01-01T00:00:00Z';expired=queue[0]['event_id']
        (self.state/'queue.json').write_text(json.dumps(queue));os.chmod(self.state/'queue.json',0o600)
        self.run_report();self.assertNotIn(expired,[e['event_id'] for e in self.load('queue.json')])
    def test_symlink_root_and_state_files_rejected(self):
        target=self.root/'elsewhere';target.mkdir(mode=0o700)
        self.state.parent.mkdir(mode=0o700);self.state.symlink_to(target,target_is_directory=True)
        with self.assertRaises(OSError): self.run_report()
        self.assertEqual(list(target.iterdir()),[])
    def test_hardlink_or_excess_permissions_fail_closed(self):
        self.run_report();identity=self.state/'identity.json'
        os.link(identity,self.root/'identity-copy')
        with self.assertRaises(ValueError): self.run_report()
        (self.root/'identity-copy').unlink();os.chmod(identity,0o644)
        with self.assertRaises(ValueError): self.run_report()
    def test_corrupt_identity_not_silently_rotated(self):
        self.run_report();path=self.state/'identity.json';path.write_text('{"broken":true}');os.chmod(path,0o600)
        with self.assertRaises(ValueError): self.run_report()
        self.assertEqual(json.loads(path.read_text()),{'broken':True})
    def test_only_bounded_allowlisted_operation_facts(self):
        self.run_report('update','failed',source='https://private.invalid/?secret=bad',duration='bad',failure='arbitrary raw error text')
        event=self.load('queue.json')[0]
        self.assertIsNone(event['operation']['source']);self.assertIsNone(event['operation']['duration_ms']);self.assertIsNone(event['operation']['failure_stage'])
        self.assertEqual(event['operation']['maintenance']['managers'],[])
    def test_native_batch_results_do_not_claim_packages_updated(self):
        receipts=self.root/'receipts';receipts.mkdir()
        (receipts/'1.command.json').write_text(json.dumps({'section':'Dnf','outcome':'command-success','command':'this must not leave the machine'}))
        self.run_report('maintenance','unknown',receipts=str(receipts))
        data=self.load('queue.json')[0]['operation']['maintenance']
        self.assertIsNone(data['updated']);self.assertIsNone(data['failed'])
        self.assertEqual(data['managers'],[{'manager':'Dnf','updated':None,'skipped':None,'failed':None,'unknown':None,'outcome':'succeeded'}])
        self.assertNotIn('this must not leave',json.dumps(data))
    def test_apt_confirmed_version_changes_only(self):
        receipts=self.root/'receipts';receipts.mkdir()
        (receipts/'1.command.json').write_text(json.dumps({'section':'Apt','outcome':'command-success'}))
        (receipts/'apt-before.tsv').write_text('a\t1\nb\t1\n');(receipts/'apt-after.tsv').write_text('a\t2\nb\t1\n')
        self.run_report('maintenance','unknown',receipts=str(receipts))
        data=self.load('queue.json')[0]['operation']['maintenance'];self.assertEqual(data['updated'],1)
        self.assertEqual(data['managers'][0]['updated'],1)
    def test_degraded_apt_inventory_never_claims_package_delta(self):
        receipts=self.root/'receipts';receipts.mkdir()
        (receipts/'1.command.json').write_text(json.dumps({'section':'Apt','outcome':'command-success'}))
        (receipts/'apt-before.tsv').write_text('a\t1\nb\t1\n');(receipts/'apt-after.tsv').write_text('a\t2\n')
        self.run_report('maintenance','unknown',receipts=str(receipts),capture_health='degraded')
        data=self.load('queue.json')[0]['operation']['maintenance']
        self.assertIsNone(data['updated']);self.assertIsNone(data['managers'][0]['updated'])
        self.assertEqual(data['managers'][0]['outcome'],'succeeded')
    def test_bounded_probe_output_and_deadline(self):
        probe=self.original_bounded
        self.assertEqual(probe([sys.executable,'-c',"print('synthetic')"],64),'synthetic')
        began=time.monotonic()
        self.assertIsNone(probe([sys.executable,'-c',"import sys\nwhile True: sys.stdout.write('x'*4096);sys.stdout.flush()"],64))
        self.assertLess(time.monotonic()-began,2.0)
        began=time.monotonic()
        self.assertIsNone(probe([sys.executable,'-c',"import time;time.sleep(20)"],64))
        self.assertLess(time.monotonic()-began,2.0)
    def test_absent_installed_runtime_has_no_temporary_hash_and_fields_bounded(self):
        saved_read=pathlib.Path.read_text;saved_hostname=module['socket'].gethostname;saved_uname=module['os'].uname
        saved_which=module['shutil'].which;saved_usage=module['shutil'].disk_usage
        def read(path,*args,**kwargs):
            value=str(path)
            if value=='/etc/os-release': return 'ID=fixture\nPRETTY_NAME="'+'e'*256+'"\nVERSION_ID="'+'v'*256+'"\nBUILD_ID="'+'b'*256+'"\n'
            if value=='/proc/uptime': return '100 0\n'
            if value=='/proc/stat': return 'btime 100\n'
            return saved_read(path,*args,**kwargs)
        try:
            pathlib.Path.read_text=read;module['socket'].gethostname=lambda:'m'*255
            module['os'].uname=lambda:types.SimpleNamespace(release='k'*255,machine='x86_64')
            module['shutil'].which=lambda name:None;module['shutil'].disk_usage=lambda path:types.SimpleNamespace(free=1,total=2)
            module['bounded_command']=lambda *args,**kwargs:None
            state={'first_install_at':None,'source_commit':'a'*40,'installed_sha256':None,'retry_count':0,'last_success_at':None}
            facts=self.original_collect(str(self.root/'absent-runtime'),str(self.runtime),'1.2.3.4',state,0)
            self.assertIsNone(facts['source_sha256']);self.assertIsNone(facts['installed_version']);self.assertIsNone(facts['source_commit'])
            for key in ('machine_name','os_edition','os_version','os_build'): self.assertEqual(len(facts[key]),128)
            self.assertEqual(facts['reporting']['identity_scope'],'native-user')
        finally:
            pathlib.Path.read_text=saved_read;module['socket'].gethostname=saved_hostname;module['os'].uname=saved_uname
            module['shutil'].which=saved_which;module['shutil'].disk_usage=saved_usage
    def test_hash_mismatch_does_not_claim_source_commit(self):
        self.run_report('update','succeeded',commit='a'*40)
        state=self.load('identity.json');self.runtime.write_text("REPARO_LINUX_VERSION='1.2.3.5'\n")
        module['bounded_command']=lambda command,limit=4096: None
        facts=self.original_collect(str(self.runtime),str(self.runtime),'1.2.3.5',state,0)
        self.assertIsNone(facts['source_commit']);self.assertIsNone(facts['entra_joined'])
        self.assertIsNone(facts['schedule']['next_due']);self.assertIsNone(facts['schedule']['last_result'])
    def test_https_response_auth_scope_redirect_and_body_bounds(self):
        sent=[]
        event={'event_id':str(uuid.uuid4())}
        class Connection:
            status=200;answer=None
            def __init__(self,host,port,timeout):
                self.owner_host=host;self.owner_port=port;self.owner_timeout=timeout
            def request(self,method,path,body,headers): sent.append((self.owner_host,self.owner_port,method,path,json.loads(body),headers,self.owner_timeout))
            def getresponse(self): return self
            def read(self,size): return self.answer[:size] if self.answer is not None else json.dumps({'accepted':True,'event_id':event['event_id']}).encode()
            def close(self): pass
        saved=module['http'].client.HTTPSConnection
        module['http'].client.HTTPSConnection=Connection
        try:
            self.assertTrue(self.original_send('a'*64,event,0.5))
            self.assertEqual(sent[0][:4],('file.thetechnologist.io',443,'POST','/api/reparo/v1/report'))
            self.assertEqual(sent[0][5]['Authorization'],'Bearer '+'a'*64)
            Connection.status=302;self.assertFalse(self.original_send('a'*64,event,0.5))
            Connection.status=200;Connection.answer=b'x'*1025;self.assertFalse(self.original_send('a'*64,event,0.5))
            Connection.answer=json.dumps({'accepted':True,'event_id':str(uuid.uuid4())}).encode();self.assertFalse(self.original_send('a'*64,event,0.5))
        finally: module['http'].client.HTTPSConnection=saved
    def test_installer_lifecycle_records_fresh_date_and_keeps_identity(self):
        # Actual shell transaction; curl/crontab and Python's HTTPS transport are
        # fixtures. HOME/XDG are disposable. No endpoint or package manager runs.
        fixture=self.root/'lifecycle';fixture.mkdir(mode=0o700);bindir=fixture/'bin';bindir.mkdir(mode=0o700)
        fake_runtime=fixture/'source-runtime';fake_runtime.write_text(source);fake_runtime.chmod(0o755)
        capture=fixture/'captured.jsonl'
        wrapper=bindir/'python3'
        injection="""
def fixture_send(secret,event,timeout):
    with open(os.environ['REGISTRY_TEST_CAPTURE'],'a',encoding='utf-8') as f: f.write(json.dumps(event)+'\\n')
    return True
send_event=fixture_send
def fixture_facts(installed,executing,version,state,queued):
    return {'machine_name':'synthetic-fixture','first_install_at':state['first_install_at'],'first_install_source':'recorded-install' if state['first_install_at'] else None,'installed_version':version_of(installed),'executed_version':version,'source_sha256':digest_file(installed),'source_commit':state['source_commit'],'package_managers':[]}
collect_facts=fixture_facts
"""
        wrapper_code='#!'+sys.executable+'\nimport os,sys\ncode=sys.stdin.read()\n'
        wrapper_code+='if "ENDPOINT_HOST=" in code:\n    code=code.replace("try: main(sys.argv[1:])",'+repr(injection+'\ntry: main(sys.argv[1:])')+')\n'
        wrapper_code+='    code=code.replace('+repr("except Exception: pass # Reporting never replaces the caller's real result.")+','+repr("except Exception: __import__('traceback').print_exc(file=os.fdopen(3,'w',closefd=False))")+')\n'
        wrapper_code+='sys.argv=sys.argv[1:]\nexec(compile(code,"fixture-stdin","exec"))\n'
        wrapper.write_text(wrapper_code)
        wrapper.chmod(0o755)
        (bindir/'curl').write_text('#!/bin/sh\nurl=;while [ "$#" -gt 0 ]; do case "$1" in -o) output=$2; shift 2;; https://*) url=$1;shift;; *) shift;; esac; done\ncase "$url" in */installer) cp "$REGISTRY_TEST_INSTALLER" "$output";; *) [ "${REGISTRY_TEST_DOWNLOAD_FAIL:-0}" = 0 ] || exit 22; cp "$REGISTRY_TEST_SOURCE" "$output";; esac\n')
        (bindir/'crontab').write_text('#!/bin/sh\nif [ "$1" = -l ]; then cat "$REGISTRY_TEST_CRON"; else [ "${REGISTRY_TEST_CRON_FAIL:-0}" = 0 ] || exit 1; cp "$1" "$REGISTRY_TEST_CRON"; fi\n')
        for name in ('curl','crontab'): (bindir/name).chmod(0o755)
        cron=fixture/'cron';cron.write_text('7 7 * * * echo preserved\n')
        env=dict(os.environ,HOME=str(fixture/'home'),XDG_DATA_HOME=str(fixture/'data'),XDG_STATE_HOME=str(fixture/'state'),PATH=str(bindir)+':'+os.environ['PATH'],REPARO_URL='https://fixture.invalid/runtime',REPARO_REPORT_SKIP='0',REPARO_REGISTRY_DISABLE='0',REGISTRY_TEST_SOURCE=str(fake_runtime),REGISTRY_TEST_CAPTURE=str(capture),REGISTRY_TEST_CRON=str(cron))
        installer=repo/'deploy/install-reparo-linux.sh'
        result=subprocess.run(['sh',str(installer),'--verbose'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode())
        self.assertTrue(capture.exists(),result.stderr.decode()+' '+result.stdout.decode())
        events=[json.loads(v) for v in capture.read_text().splitlines()]
        self.assertEqual(len(events),1);event=events[0]
        self.assertEqual(event['event_type'],'install');self.assertEqual(event['operation']['outcome'],'succeeded')
        self.assertIsNotNone(event['facts']['first_install_at']);first=event['facts']['first_install_at']
        self.assertIn(b'Reparo device reporting:',result.stderr)
        ident=event['installation_id']
        result=subprocess.run(['sh',str(installer),'--verbose'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode())
        event=json.loads(capture.read_text().splitlines()[-1]);self.assertEqual(event['event_type'],'update')
        self.assertEqual(event['installation_id'],ident);self.assertEqual(event['facts']['first_install_at'],first)
        self.assertNotIn(b'Reparo device reporting:',result.stderr)
        self.assertIn('echo preserved',cron.read_text())
        # A validated installer failure owns its completion report. The parent
        # emits only its start record, rather than a second failed completion.
        env['REPARO_INSTALLER_URL']='https://fixture.invalid/installer';env['REGISTRY_TEST_INSTALLER']=str(installer)
        env['REGISTRY_TEST_CRON_FAIL']='1'
        before=len(capture.read_text().splitlines())
        result=subprocess.run(['sh',str(fake_runtime),'--new'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
        self.assertNotEqual(result.returncode,0)
        delta=[json.loads(v) for v in capture.read_text().splitlines()[before:]]
        self.assertEqual(len(delta),2,[(v['event_type'],v['operation']['outcome']) for v in delta])
        self.assertEqual([v['operation']['outcome'] for v in delta],['started','failed'])
        self.assertEqual(delta[-1]['operation']['failure_stage'],'schedule')
        # A child which fails before any verified runtime/report utility exists
        # cannot claim ownership; the parent still records that failure once.
        env['REGISTRY_TEST_CRON_FAIL']='0';env['REGISTRY_TEST_DOWNLOAD_FAIL']='1'
        before=len(capture.read_text().splitlines())
        result=subprocess.run(['sh',str(fake_runtime),'--new'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
        self.assertNotEqual(result.returncode,0)
        delta=[json.loads(v) for v in capture.read_text().splitlines()[before:]]
        self.assertEqual(len(delta),2);self.assertEqual([v['operation']['outcome'] for v in delta],['started','failed'])
        self.assertEqual(delta[-1]['operation']['failure_stage'],'installer-execution')
    def test_no_registration_or_commands_or_redirect_following(self):
        self.assertEqual(module['ENDPOINT_HOST'],'file.thetechnologist.io')
        self.assertEqual(module['ENDPOINT_PATH'],'/api/reparo/v1/report')
        self.assertNotIn('urlopen',code)
        self.assertNotIn('eval(',code)
        self.assertNotIn('/enroll',code)
        self.assertIn("if response.status!=200: return False",code)

unittest.main(argv=['registry-tests'],verbosity=2)
TEST_PY
# Utility commands and the explicit opt-out do not create registry identity state.
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
HOME="$fixture/home" XDG_DATA_HOME="$fixture/data" XDG_STATE_HOME="$fixture/state" sh "$repo/linux/reparo-linux" --version >/dev/null
HOME="$fixture/home" XDG_DATA_HOME="$fixture/data" XDG_STATE_HOME="$fixture/state" sh "$repo/linux/reparo-linux" --help >/dev/null
[ ! -e "$fixture/state/reparo/registry" ]
HOME="$fixture/home" XDG_DATA_HOME="$fixture/data" XDG_STATE_HOME="$fixture/state" REPARO_REPORT_SKIP=0 REPARO_REGISTRY_DISABLE=1 REPARO_REPORT_OUTCOME=succeeded sh "$repo/linux/reparo-linux" --report-lifecycle
[ ! -e "$fixture/state/reparo/registry" ]
printf '%s\n' 'Automatic native registry private identity, honest first-install date, bounded retry queue, provenance, receipt counts and offline opt-out passed; HTTPS mocked.'
