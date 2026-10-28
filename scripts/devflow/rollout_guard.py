"""Owner-authorized append-only rollout; unsupported variants retain their original checks."""
from __future__ import annotations
import collections
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request

SPEC = importlib.util.spec_from_file_location('migration', Path(__file__).with_name('apply_optimization.py'))
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)
ROOT = Path('.')
OUT = Path('artifacts/dev-flow')
MANIFEST = OUT/'rollout.json'
AUDITED_BASE = 'aac301b9a9a89e027f6d99864437eb750a4202ca'


def git(*args):
    return m.git(*args,cwd=ROOT)


def content(ref,path):
    return subprocess.check_output(['git','show',f'{ref}:{path}'],text=True)


def save(report):
    MANIFEST.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')


def main_policy():
    cfg=json.loads(content('origin/main',m.POLICY))
    if cfg.get('revision') != m.VERSION:
        raise ValueError('CANONICAL_ACTIVATION_MISSING')
    if content('origin/main','scripts/devflow/apply_optimization.py') != Path('scripts/devflow/apply_optimization.py').read_text():
        raise ValueError('MIGRATOR_NOT_IDENTICAL_TO_APPROVED_MAIN')


def plan():
    main_policy()
    canonical={p:m.load_yaml(content(AUDITED_BASE,p)) for p in m.ECO}
    canonical_continuation=content(AUDITED_BASE,m.CONTINUATION)
    original=m.transform
    def guarded(files):
        filtered=dict(files); notes=[]; unknown=[]
        for p in [m.PC,m.LIVE,*m.ECO]:
            if p not in filtered:continue
            try:
                cfg=m.load_yaml(filtered[p])
                if not isinstance(cfg.get('jobs'),dict):raise ValueError('UNKNOWN_JOB_SHAPE')
                if p==m.LIVE and not isinstance(cfg.get('on'),dict):raise ValueError('UNKNOWN_EVENT_SHAPE')
            except (ValueError,m.yaml.YAMLError) as exc:
                filtered.pop(p,None)
                if p in m.ECO:unknown.append(p)
                notes.append({'original_workflow_retained':p,'reason':str(exc)[:300]})
        for p in m.ECO:
            if p not in filtered:continue
            cfg=m.load_yaml(filtered[p]); events=cfg.get('on',{})
            supported=(isinstance(events,dict) and set(events) <= {'push','pull_request','workflow_dispatch'})
            if supported:
                for event in ['push','pull_request']:
                    rule=events.get(event) or {}
                    supported=supported and isinstance(rule,dict) and set(rule) <= {'branches','paths'}
            if cfg.get('jobs') != canonical[p].get('jobs') or not supported:unknown.append(p)
        if unknown:
            for p in m.ECO:filtered.pop(p,None)
            notes.append({'eco_deduplication':'RETAINED_UNAUDITED_BRANCH_VARIANT','paths':unknown})
        if m.CONTINUATION in filtered and filtered[m.CONTINUATION] != canonical_continuation and 'review_execution_plan' not in filtered[m.CONTINUATION]:
            filtered.pop(m.CONTINUATION,None)
            notes.append({'harness_runtime_advice':'CUSTOM_CONTINUATION_PRESERVED_POLICY_DOCS_APPLIED'})
        changes,receipt=original(filtered)
        receipt['notes'].extend(notes)
        import ast
        for p,text in changes.items():
            if p.endswith('.py'):ast.parse(text,filename=p)
            if p.endswith('.json'):json.loads(text)
            if p.endswith('.yml'):m.load_yaml(text)
        return changes,receipt
    m.transform=guarded
    report=m.plan_branches(ROOT,MANIFEST)
    counts=collections.Counter(str(n.get('eco_deduplication',n.get('harness_runtime_advice',''))) for r in report['rows'] for n in r['notes'])
    print('PLAN_NOTES='+json.dumps(dict(counts)))


def api(path,data):
    req=urllib.request.Request('https://api.github.com/repos/'+os.environ['GITHUB_REPOSITORY']+'/'+path,
        data=json.dumps(data).encode(),method='POST',headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],
        'Accept':'application/vnd.github+json','Content-Type':'application/json','X-GitHub-Api-Version':'2022-11-28'})
    with urllib.request.urlopen(req,timeout=90) as response:return json.load(response)


def export_object_spec(row,uploaded):
    parent=row['before']; after=row['after']; elements=[]
    for path in row['changes']:
        mode=git('ls-tree',after,'--',path).split()[0]
        sha=git('rev-parse',after+':'+path)
        if sha not in uploaded:
            result=api('git/blobs',{'content':content(after,path),'encoding':'utf-8'})
            if result['sha'] != sha:raise ValueError('REMOTE_BLOB_MISMATCH')
            uploaded.add(sha)
        elements.append({'path':path,'mode':mode,'type':'blob','sha':sha})
    return {'branch':row['branch'],'before':parent,'base_tree':git('rev-parse',parent+'^{tree}'),
            'prepared_commit':after,'tree':row['tree'],'tree_elements':elements}


def publish():
    main_policy()
    report=json.loads(MANIFEST.read_text()); known=set()
    refs=git('for-each-ref','--format=%(objectname)','refs/remotes/origin/').splitlines()
    for sha in set(refs):
        for line in git('ls-tree','-r',sha,'--','.github/workflows').splitlines():
            meta,path=line.split('\t',1);known.add((path,meta.split()[2]))
    blocked=[]
    for row in report['rows']:
        if row['status'] != 'PREPARED_NOT_PUBLISHED':continue
        needed={(p,git('rev-parse',row['after']+':'+p)) for p in row['changes'] if p.startswith('.github/workflows/')}
        missing=needed-known
        if missing:
            row['status']='NEEDS_WORKFLOW_AUTHORIZATION'
            row['missing_workflow_blobs']=[list(pair) for pair in sorted(missing)]
            blocked.append(row)
    save(report)
    remaining=set(tuple(pair) for row in blocked for pair in row['missing_workflow_blobs'])
    representatives=[];uploaded=set()
    while remaining:
        row=max(blocked,key=lambda r:len({tuple(p) for p in r['missing_workflow_blobs']} & remaining))
        covered={tuple(p) for p in row['missing_workflow_blobs']} & remaining
        if not covered:raise ValueError('COVERAGE_SELECTION_FAILED')
        spec=export_object_spec(row,uploaded);spec['new_workflow_variants']=len(covered)
        representatives.append(spec);remaining-=covered
        print('CONNECTOR_AUTHORIZATION_REQUIRED='+json.dumps({k:v for k,v in spec.items() if k!='tree_elements'}),flush=True)
    report['connector_authorizations']=representatives;save(report)
    (OUT/'connector-authorizations.json').write_text(json.dumps(representatives,indent=2)+'\n')
    try:
        m.publish(ROOT,MANIFEST)
    except RuntimeError as exc:
        if str(exc) != 'ROLLOUT_INCOMPLETE_SEE_RECEIPT':raise
        print('PARTIAL_ROLLOUT_CONNECTOR_PUBLICATION_REQUIRED',flush=True)
    finally:
        report=json.loads(MANIFEST.read_text())
        counts=dict(collections.Counter(row['status'] for row in report['rows']))
        summary={'revision':m.VERSION,'run_id':os.environ.get('GITHUB_RUN_ID'),'counts':counts,'branch_count':len(report['rows']),
                 'connector_authorizations':representatives,'runtime_regression_on_every_branch_not_claimed':True}
        (OUT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
        print('ROLLOUT_SUMMARY='+json.dumps({k:v for k,v in summary.items() if k!='connector_authorizations'}),flush=True)


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    if len(sys.argv)!=2 or sys.argv[1] not in {'plan','publish'}:raise SystemExit('Expected plan|publish')
    {'plan':plan,'publish':publish}[sys.argv[1]]()
