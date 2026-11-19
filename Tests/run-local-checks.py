#!/usr/bin/env python3
"""Run the existing GitHub workflow's checks locally, using only the stdlib.
Logs/receipts stay private outside Git or inside an explicitly ignored directory.
"""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

REPO=Path(__file__).resolve().parents[1]
WORKFLOW=REPO/'.github/workflows/test-steam-headless.yml'
MANIFEST=re.compile(r'https://raw\.githubusercontent\.com/16thdoc/Reparo/([0-9a-f]{40})/deploy/reparo-release\.json\Z')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(['git','-C',str(REPO),*args],text=True,stderr=subprocess.PIPE).strip()


def workflow_steps(text,job):
    """Read the narrow, checked workflow layout; fail on unsupported run forms.

    No general YAML dependency: workflow expressions, action execution and custom
    shell interpolation are deliberately unsupported rather than guessed.
    """
    selected=False;step=None;result=[];lines=text.splitlines();index=0
    while index<len(lines):
        line=lines[index]
        match=re.fullmatch(r'  ([A-Za-z0-9_-]+):\s*',line)
        if match:
            selected=match[1]==job;step=None;index+=1;continue
        if not selected:
            index+=1;continue
        match=re.fullmatch(r'      - name: (.+)',line)
        if match:
            step={'name':match[1].strip(),'shell':None};index+=1;continue
        if line.startswith('      - uses:'):
            step=None;index+=1;continue
        if step is not None and line.startswith('        shell: '):
            step['shell']=line.split(':',1)[1].strip();index+=1;continue
        if step is not None and line.startswith('        run: '):
            value=line[len('        run: '):]
            if value=='|':
                body=[];index+=1
                while index<len(lines):
                    following=lines[index]
                    if following and not following.startswith('          '): break
                    body.append(following[10:] if following else '')
                    index+=1
                script='\n'.join(body)+'\n'
            else:
                if value.startswith(('|','>','"',"'")): raise ValueError('Unsupported workflow run scalar')
                script=value+'\n';index+=1
            if '${{' in script: raise ValueError('Workflow expressions require an explicit runner update')
            result.append(dict(step,script=script));step=None;continue
        index+=1
    if not result: raise ValueError('No runnable workflow steps found for '+job)
    expected={'powershell':{'powershell','pwsh'},'native-installer':{None,'bash'}}[job]
    if any(item['shell'] not in expected for item in result): raise ValueError('Unsupported workflow shell')
    return result


def private_output(path):
    path=Path(os.path.abspath(path))
    for item in (path,*path.parents):
        if item.is_symlink() or (hasattr(item,'is_junction') and item.is_junction()): raise ValueError('Output cannot pass through a filesystem link')
    ancestor=path
    while not ancestor.exists(): ancestor=ancestor.parent
    probe=subprocess.run(['git','-C',str(ancestor),'rev-parse','--show-toplevel'],text=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    if probe.returncode==0:
        repository=Path(probe.stdout.strip()).resolve()
        relative=path.relative_to(repository)
        if '.git' in (part.lower() for part in relative.parts): raise ValueError('Output cannot be stored in Git metadata')
        ignored=subprocess.run(['git','-C',str(repository),'check-ignore','--quiet','--no-index',str(path)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        if ignored.returncode!=0: raise ValueError('Output inside Git must be explicitly ignored; choose a private external directory')
    if path.exists() and any(path.iterdir()): raise ValueError('Output directory is not empty; use a new path to preserve earlier evidence')
    path.mkdir(mode=0o700,parents=True,exist_ok=True)
    if os.name!='nt': path.chmod(0o700)
    return path


def windows_engines():
    system=Path(os.environ.get('SystemRoot',r'C:\Windows'))
    ps5=system/'System32/WindowsPowerShell/v1.0/powershell.exe'
    ps7=shutil.which('pwsh')
    if not ps5.is_file() or not ps7: raise ValueError('Windows profile requires Windows PowerShell5.1 and PowerShell7 (pwsh)')
    clean=dict(os.environ,PSModulePath='')
    module_path=subprocess.check_output([str(ps5),'-NoProfile','-NonInteractive','-Command',"[Environment]::GetEnvironmentVariable('PSModulePath','Machine')"],env=clean,text=True).strip()
    if not module_path: module_path=str(ps5.parent/'Modules')
    return {'powershell':str(ps5),'pwsh':ps7},module_path


def secure_windows_directory(path,engine,env):
    # This is a newly created output directory only; no existing configuration ACL.
    quoted="'"+str(path).replace("'","''")+"'"
    code="$ErrorActionPreference='Stop'; $path="+quoted+"; $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User; $acl=New-Object Security.AccessControl.DirectorySecurity; $acl.SetAccessRuleProtection($true,$false); $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))); ([IO.DirectoryInfo]$path).SetAccessControl($acl)"
    result=subprocess.run([engine,'-NoProfile','-NonInteractive','-Command',code],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    if result.returncode: raise ValueError('Cannot secure private Windows output directory: '+result.stderr.strip())


def manifest_preflight(url):
    if not MANIFEST.fullmatch(url): raise ValueError('Manifest must be the fixed Reparo raw GitHub path at a full immutable commit')
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*args,**kwargs): return None
    request=urllib.request.Request(url,headers={'User-Agent':'Reparo-Artifact-Verification/1.0','Cache-Control':'no-cache'})
    with urllib.request.build_opener(NoRedirect()).open(request,timeout=30) as response:
        raw=response.read(16385)
        if response.status!=200 or len(raw)>16384: raise ValueError('Manifest unavailable or oversized')
    value=json.loads(raw)
    if hashlib.sha256(raw).hexdigest()!=sha(REPO/'deploy/reparo-release.json'):
        raise ValueError('Public manifest differs from this checkout; publish the reviewed pin or use its matching checkout')
    return {'url':url,'sha256':hashlib.sha256(raw).hexdigest(),'version':value.get('version'),'source_commit':value.get('commit')}


def adapt_step(step,profile,manifest_url):
    script=step['script']
    if profile=='windows':
        # All existing assertions are unchanged. Make ordinary test invocation
        # failures produce a failing process, regardless of a fixture's LASTEXITCODE.
        core="$env:PSModulePath=[Environment]::GetEnvironmentVariable('PSModulePath','Machine')\n"
        if step['shell']=='pwsh': core="$env:PSModulePath=(Join-Path $PSHOME 'Modules')+';'+[Environment]::GetEnvironmentVariable('PSModulePath','Machine')\n"
        script="$ErrorActionPreference='Stop'\n"+core+script
        if not re.search(r'(?m)^\s*exit\s+0\s*$',script):
            script+="\nif (-not $?) { throw 'Local workflow step failed' }; exit 0\n"
    elif 'pilot_env=(' in script:
        original='REPARO_RELEASE_URL=https://raw.githubusercontent.com/$GITHUB_REPOSITORY/$GITHUB_SHA/deploy/reparo-release.json'
        if script.count(original)!=1: raise ValueError('HTTPS workflow manifest binding changed; review the local adaptation')
        script=script.replace(original,'REPARO_RELEASE_URL=$REPARO_LOCAL_MANIFEST_URL')
        # Verification-only curl wrapper identifies real download observations.
        marker='chmod +x "$sandbox/bin/crontab"'
        if script.count(marker)!=1: raise ValueError('HTTPS workflow sandbox changed; review curl adaptation')
        script=script.replace(marker,marker+"\ncat > \"$sandbox/bin/curl\" <<'REPARO_LOCAL_CURL'\n#!/usr/bin/env sh\nexec \"$REPARO_LOCAL_CURL\" \"$@\" -A 'Reparo-Artifact-Verification/1.0'\nREPARO_LOCAL_CURL\nchmod +x \"$sandbox/bin/curl\"\n")
        script+="\ntest ! -e \"$sandbox/state/reparo/registry\"\n"
    return script


def run_step(command,env,log_path,timeout=1800):
    start=time.monotonic()
    with log_path.open('xb') as log:
        process=subprocess.Popen(command,cwd=REPO,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=os.name!='nt')
        try: code=process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name=='nt':
                killer=Path(os.environ.get('SystemRoot',r'C:\Windows'))/'System32/taskkill.exe'
                subprocess.run([str(killer),'/PID',str(process.pid),'/T','/F'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
            else:
                import signal
                os.killpg(process.pid,signal.SIGKILL)
            process.wait(timeout=10);code=124
        except BaseException:
            if process.poll() is None:
                if os.name=='nt':
                    killer=Path(os.environ.get('SystemRoot',r'C:\Windows'))/'System32/taskkill.exe'
                    subprocess.run([str(killer),'/PID',str(process.pid),'/T','/F'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
                else:
                    import signal
                    os.killpg(process.pid,signal.SIGKILL)
            raise
    return code,round(time.monotonic()-start,3)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',choices=('windows','linux'),required=True)
    parser.add_argument('--output-dir',type=Path)
    parser.add_argument('--manifest-url',help='Linux HTTPS fixture: fixed raw GitHub production manifest at a full public commit')
    parser.add_argument('--list',action='store_true',help='Show exact workflow step names without executing or writing')
    args=parser.parse_args()
    profile=args.profile
    text=WORKFLOW.read_text(encoding='utf-8-sig')
    steps=workflow_steps(text,'powershell' if profile=='windows' else 'native-installer')
    if args.list:
        print(json.dumps({'profile':profile,'workflow':str(WORKFLOW),'steps':[{'name':item['name'],'shell':item['shell']} for item in steps]},indent=2));return 0
    if not args.output_dir: parser.error('--output-dir is required unless --list is used')
    if (profile=='windows')!=(os.name=='nt'): parser.error('Run the Windows profile on Windows and the Linux profile on native Linux')
    if profile=='windows' and args.manifest_url: parser.error('--manifest-url applies only to the Linux HTTPS step')
    output=private_output(args.output_dir)
    head=git('rev-parse','HEAD')
    env={key:value for key,value in os.environ.items() if not key.startswith('REPARO_')}
    env.update(REPARO_REPORT_SKIP='1',NO_COLOR='1',GITHUB_REPOSITORY='16thdoc/Reparo',GITHUB_SHA=head)
    engines={};manifest=None
    if profile=='windows':
        engines,module_path=windows_engines();env['PSModulePath']=module_path
        secure_windows_directory(output,engines['powershell'],env)
    else:
        if not sys.platform.startswith('linux'): parser.error('The Linux profile requires native Linux')
        for required in ('bash','sh','git','curl','python3'):
            if not shutil.which(required): raise ValueError('Missing local check dependency: '+required)
        manifest_url=args.manifest_url or 'https://raw.githubusercontent.com/16thdoc/Reparo/'+head+'/deploy/reparo-release.json'
        manifest=manifest_preflight(manifest_url)
        env.update(REPARO_LOCAL_MANIFEST_URL=manifest_url,REPARO_LOCAL_CURL=str(Path(shutil.which('curl')).resolve()))
    receipt={'schema':'reparo-local-checks-1','profile':profile,'started_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'git_head':head,'git_status':git('status','--short'),'workflow_sha256':sha(WORKFLOW),'runner_sha256':sha(__file__),'source_sha256':{path:sha(REPO/path) for path in ('Reparo.ps1','linux/reparo-linux','deploy/install-reparo-linux.sh','deploy/reparo-release.json','deploy/reparo-candidate.json')},'report_skip':'1','manifest':manifest,'steps':[],'result':'running'}
    receipt_path=output/'receipt.json'
    def save():
        temporary=output/'receipt.json.tmp'
        temporary.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8');os.replace(temporary,receipt_path)
    save()
    temporary=Path(tempfile.mkdtemp(prefix='reparo-local-checks-'))
    env['RUNNER_TEMP']=str(temporary)
    try:
        for index,step in enumerate(steps,1):
            name=re.sub('[^a-z0-9]+','-',step['name'].lower()).strip('-')
            log_path=output/(f'{index:02d}-'+name+'.log')
            script=adapt_step(step,profile,manifest['url'] if manifest else None)
            script_path=temporary/(f'{index:02d}-step.'+('ps1' if profile=='windows' else 'sh'))
            script_path.write_text(script,encoding='utf-8-sig' if profile=='windows' else 'utf-8',newline='\n')
            command=[engines[step['shell']],'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(script_path)] if profile=='windows' else [shutil.which('bash'),'--noprofile','--norc','-e',str(script_path)]
            print(f'RUN {index}/{len(steps)} {step["name"]}',flush=True)
            code,duration=run_step(command,env,log_path)
            receipt['steps'].append({'name':step['name'],'shell':step['shell'] or 'bash','exit_code':code,'duration_seconds':duration,'log':log_path.name,'log_sha256':sha(log_path)})
            save();print(('PASS' if code==0 else 'FAIL')+f' ({duration}s) '+step['name'],flush=True)
            if code!=0:
                receipt['result']='failed';receipt['failed_step']=step['name'];return code or 1
        receipt['git_head_finished']=git('rev-parse','HEAD')
        receipt['finished_workflow_sha256']=sha(WORKFLOW)
        receipt['finished_source_sha256']={path:sha(REPO/path) for path in receipt['source_sha256']}
        receipt['source_bytes_unchanged']=receipt['finished_source_sha256']==receipt['source_sha256'] and receipt['finished_workflow_sha256']==receipt['workflow_sha256']
        if not receipt['source_bytes_unchanged']:
            receipt['result']='failed';receipt['failed_step']='Source/workflow changed during checks';return 1
        receipt['result']='passed';return 0
    except BaseException as error:
        if receipt['result']=='running': receipt['result']='interrupted' if isinstance(error,KeyboardInterrupt) else 'failed'
        receipt['runner_error_type']=type(error).__name__
        raise
    finally:
        receipt['finished_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        receipt['temporary_fixture_root_cleaned']=False
        # This exact directory was created by this process. It is never a user
        # supplied deletion target, repository, HOME or production installation.
        actual=temporary.resolve()
        if actual.parent!=Path(tempfile.gettempdir()).resolve() or not actual.name.startswith('reparo-local-checks-'): raise ValueError('Unsafe owned-fixture cleanup')
        shutil.rmtree(actual)
        receipt['temporary_fixture_root_cleaned']=True;save()
        print('Receipt: '+str(receipt_path),flush=True)

if __name__=='__main__':
    try: raise SystemExit(main())
    except (OSError,ValueError,subprocess.CalledProcessError,urllib.error.URLError) as error:
        print('Local checks unavailable: '+str(error),file=sys.stderr);raise SystemExit(2)
