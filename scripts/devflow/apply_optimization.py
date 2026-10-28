"""Idempotent, control-only migration. Never rewrites history or product evidence."""
from __future__ import annotations
import argparse
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import yaml

VERSION = 'DEV-FLOW-2026-10-28-R1'
WORKFLOWS = '.github/workflows/'
ECO_NAMES = [
    'eco-arch2-a14-4-live-exact.yml',
    'eco-arch2-a14-5-staged-exact.yml',
    'eco-arch2-a14-5-r2-latency-exact.yml',
    'eco-arch2-a14-5-r3-live-staged-exact.yml',
    'eco-arch2-a14-6-r1-fine-latency-exact.yml',
    'eco-arch2-a14-6-r2-staged-global-a4-exact.yml',
]
ECO = [WORKFLOWS + name for name in ECO_NAMES]
PC = WORKFLOWS + 'project-control.yml'
LIVE = WORKFLOWS + 'v0-live2-r1-targeted-windows.yml'
POLICY = 'config/control/harness/development-flow-policy.v1.json'
PLAN = 'docs/plans/DEVELOPMENT_FLOW_OPTIMIZATION_RU.md'
MODULE = 'scripts/harness/development_flow.py'
CONTINUATION = 'scripts/harness/continuation.py'
DOCS = ['AGENTS.md', 'HARNESS_CONTROL.md', 'docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md',
        'docs/plans/PROJECT_DEVELOPMENT_FOCUS_RU.md',
        'docs/network/SEAMLESS_WORLD_ROADMAP_RU.md',
        'docs/plans/PLAYABLE_NETWORK_MILESTONES_RU.md']
PATHS = [*ECO, PC, LIVE, POLICY, PLAN, MODULE, CONTINUATION, *DOCS]

class Loader(yaml.SafeLoader):
    pass
Loader.yaml_implicit_resolvers = copy.deepcopy(yaml.SafeLoader.yaml_implicit_resolvers)
for char, resolvers in list(Loader.yaml_implicit_resolvers.items()):
    Loader.yaml_implicit_resolvers[char] = [(tag, exp) for tag, exp in resolvers
                                          if tag != 'tag:yaml.org,2002:bool']
Loader.add_implicit_resolver('tag:yaml.org,2002:bool', re.compile(r'^(?:true|false)$', re.I), list('tTfF'))

def load_yaml(text):
    value = yaml.load(text, Loader=Loader)
    if not isinstance(value, dict):
        raise ValueError('WORKFLOW_NOT_MAPPING')
    return value

def dump_yaml(value):
    return yaml.safe_dump(value, sort_keys=False, allow_unicode=True, width=120)

POLICY_VALUE = {
    'schema': 'distributed_world_simulator.development_flow_policy.v1',
    'revision': VERSION,
    'authority': 'OWNER_REQUEST_2026_10_27_RESUMED_2026_10_28',
    'routine_risks': ['LOW', 'MEDIUM'],
    'one_independent_actor_may_cover_review_and_verification': True,
    'existing_required_roles_and_predicates_preserved': True,
    'historical_work_orders_and_verdicts_are_immutable': True,
    'trusted_exact_machine_evidence_reused_by_default': True,
    'new_execution_requires_concrete_reason': True,
    'high_critical_keep_separate_responsibilities': True,
    'unknown_risk_uses_conservative_route': True,
    'implementer_cannot_self_accept': True,
    'runtime_test_launcher_assets_engine_change_invalidates_relevant_evidence': True,
    'docs_reuse_requires_explicit_content_equivalence_receipt': True,
    'performance_goals_do_not_waive_functional_failures': True,
    'small_net_p99_miss_is_advisory': True,
    'no_automatic_product_merge_or_default_enablement': True,
    'wip': {'primary_product': 1, 'integration': 1, 'urgent_repair_or_infrastructure': 1},
    'pilot_metrics': ['review_to_integration', 'job_queue_seconds', 'job_runtime_seconds',
                      'duplicate_suite_invocations', 'new_material_findings', 'escaped_regressions'],
}

MODULE_TEXT = '''"""Execution advice; never changes role requirements, verdicts or acceptance gates."""
from __future__ import annotations
from typing import Any


def execution_plan(work_order: dict[str, Any]) -> dict[str, Any]:
    risk = str(work_order.get("risk_class", "UNKNOWN"))
    roles = work_order.get("required_review_roles", [])
    routine = (risk in {"LOW", "MEDIUM"} and isinstance(roles, list)
               and bool(roles) and all(isinstance(role, str) for role in roles) and set(roles) <= {"IMPLEMENTER", "REVIEWER", "VERIFIER"}
               and not work_order.get("human_review_required", False)
               and not work_order.get("independent_execution_required", False)
               and not work_order.get("separate_machine_required", False))
    return {
        "policy_revision": "DEV-FLOW-2026-10-28-R1",
        "risk_class": risk,
        "mode": "SINGLE_INDEPENDENT_REVIEW_BATCH" if routine else "RISK_REQUIRED_SEPARATE_ROLES",
        "same_independent_actor_may_cover_reviewer_and_verifier": routine,
        "reuse_trusted_exact_machine_evidence": True,
        "explicit_work_order_execution_requirements_take_precedence": True,
        "existing_roles_predicates_and_verdict_formats_unchanged": True,
        "implementer_self_acceptance_allowed": False,
        "scope_expansion_requires_new_risk_decision": True,
        "repair_review_scope": "CHANGED_SURFACE_AND_RELEVANT_REGRESSIONS",
    }
'''

PLAN_TEXT = '''# Ускорение разработки: действующий план

Ревизия: **DEV-FLOW-2026-10-28-R1**. Основание: решение владельца применить аудит
к Harness, CI, дорожной карте и рабочим веткам. Это изменение процесса,
не признание прежних FAIL успешными и не разрешение автоматически сливать
продуктовые PR или включать экспериментальные режимы по умолчанию.

## Порядок работы и приёмки

Для LOW/MEDIUM один независимый от Implementer участник выполняет единый
содержательный разбор кода и машинных результатов и может закрыть обязанности
Reviewer и Verifier в одной сессии. Обязательные роли и форматы записей старых
Work Orders сохраняются: подпись одной роли нельзя выдавать за подпись другой.
Новая машина и полный повтор зелёной матрицы по умолчанию не нужны.
Явное требование независимого исполнения в действующем Work Order сохраняется.

HIGH/CRITICAL: отдельные обязанности ревью/верификации, проверки существенных
отказов и все человеческие решения остаются. Wire, persistence, authority,
recovery, threading, numerical algorithms, engine/precision и вычисление verdict
нельзя понижать до LOW из-за маленького diff или расположения в tests/.
Точное происхождение результатов, SHA/TREE, команды, exit code, явные skips
и контроль целостности остаются обязательными. Implementer не принимает себя.

Один основной review. После исправления проверяется исправленная причина и
затронутые зависимости. Новое пожелание, расширение численного диапазона или
оптимизационная цель сначала классифицируются: нарушенный контракт / новая
область применения / неблокирующее улучшение. Новое улучшение не становится
неявным условием завершения существующей задачи.

Чистая правка отчёта допускает повторное использование результата только при
явной проверке неизменности всех исполняемых входов. Историческому run не
приписывается новый SHA. Изменение кода, теста, launcher, fixtures, assets,
настроек импорта или движка требует соответствующей перепроверки.

## CI

Project Control запускает общий discovery один раз вместо повторного запуска
его модулей. LIVE2 не запускает дорогую графическую матрицу на docs-only diff,
а отмена устаревшего run ограничивается тем же PR/ref.

Для накопительной цепочки ECO A14.4–A14.6 единым автоматическим входом является
последний существующий workflow, только когда машинная проверка подтверждает
покрытие всех прежних script-вызовов, PASS-маркеров и engine/platform условий.
Старые workflows доступны через workflow_dispatch для исторического повтора.
При несовместимости ветки дедупликация не применяется молча: старые проверки
остаются, причина публикуется в rollout receipt. Уникальные suites не удаляются.

Быстрые проверки на PR — целевой бюджет 5–10 минут без длинной очереди.
Длинные soak и полные исторические матрицы назначаются на итоговый кандидат,
периодически и при изменении опасной области; настоящие recovery/protocol
негативные проверки нельзя переносить за выпуск затронутого продукта.
INFRA_ERROR, PRODUCT_FAIL и PERF_GOAL_MISS рассматриваются раздельно.

## Продуктовые приоритеты

**NET:** играбельная основа DONE_FOR_NOW по малому превышению p99; прежние
строгие отчёты остаются FAIL. Следующая продуктовая цель — N3 R0: реальный
World Directory и два изолированных authority-процесса, затем N4 transfer и
N5 seamless handoff. Checksum/reconnect #815 остаётся функциональным блокером
затронутого режима, но не останавливает независимую работу N3 на безопасной базе.

**ECO:** довести один составной R2F-кандидат до решения об интеграции и настоящего
GUI/backlog испытания. Плавный GUI и достаточная скорость canonical tick — разные
критерии. Зафиксировать поддерживаемый масштаб; не обещать секунду на n256 без
измерения. Не создавать новую цепочку ремонта ради небольших p99 отклонений.

**FABRIC:** завершать интеграцию проверенных recovery/численных ремонтов.
Граничные сценарии вроде 16/17 и crash/restart остаются регрессиями.
Согласовывать численную область до нового дорогостоящего круга испытаний.

**ENGINE48:** проверить наличие нужного native editor и его SHA на фактическом
Linux runner до дорогого запуска. Одна пригодная среда и один точный acceptance;
готовность Windows не доказывает готовность Linux.

**CONTROL:** один содержательный независимый review и автоматическое оформление
пакета evidence; не запускать отдельный полный цикл только ради формы отчёта.
Встроенный execution_plan объясняет объединение обычных ролей, но не подменяет
их результаты и не меняет исторический ledger.

## Незавершённая работа и интеграция

Пилотный лимит: одна основная продуктовая задача, одна задача интеграции и одна
срочная задача инфраструктуры/исправления. На направление — одна активная
интеграционная ветка; диагностические шаги — commits и receipts, не бесконечные
новые обязательные PR. Исследовано, безопасно интегрировать и готово по умолчанию
— три разных решения. Составной кандидат проверяется как совместная сборка.

## Распространение и проверка эффекта

Rollout добавляет commits поверх существующих heads; исходные SHA и изменения
записываются в JSON receipt. Нет force-push, удаления веток и переписывания старых
протоколов испытаний. При движении ветки после снимка запись отклоняется.
Старые локальные checkout и уже выполняющиеся процессы сами не обновляются:
следующая сессия делает fetch и читает новые правила; исторический exact SHA
остаётся воспроизводимым. Старые зелёные статусы не переносятся на новый HEAD.

Двухнедельный пилот: время ready-for-review→integration, ожидание отдельно от
исполнения jobs, повторные suites, полезные новые findings и регрессии после
интеграции. Цель сократить обычную приёмку вдвое — гипотеза, а не готовый результат.
'''

NOTICE = '''<!-- DEV-FLOW-2026-10-28-R1 -->
## Действующее обновление процесса — 28 октября 2026

Применяйте `docs/plans/DEVELOPMENT_FLOW_OPTIMIZATION_RU.md` и
`config/control/harness/development-flow-policy.v1.json`: один независимый
содержательный разбор LOW/MEDIUM с повторным использованием достоверного CI;
усиленные HIGH/CRITICAL и явные execution-требования сохраняются. Ремонт
проверяется по изменённой области, новые улучшения не расширяют приёмку молча.
NET: малые p99 отклонения неблокирующие; приоритет N3. ECO: R2F и backlog;
FABRIC: интеграция проверенных ремонтов; ENGINE48: пригодный Linux executor.
Прежние FAIL, Work Orders, source SHA и запреты на продуктовый merge не отменены.
<!-- /DEV-FLOW-2026-10-28-R1 -->

'''


def _invocations(job):
    result = set()
    for step in job.get('steps', []):
        for line in str(step.get('run', '')).splitlines():
            m = re.search(r'--script\s+(res://\S+)([^\n]*)', line)
            if m:
                tail = re.split(r'\s*(?:\||>|\s2>)', m.group(2))[0].strip()
                prefix = line[:m.start()].strip()
                result.add((m.group(1), tail, prefix))
            if re.search(r'python3?\s+validation/.*run_exact\.py', line):
                result.add(('PYTHON_EXACT', re.sub(r'python3?\s+', '', line).strip()))
    return result


def _markers(job):
    return set(re.findall(r'ECO_ARCH2_[A-Z0-9_]+ PASS', json.dumps(job)))


def _engine_pins(job):
    text = json.dumps(job)
    return (set(re.findall(r'\b[0-9a-f]{64}\b', text)),
            set(re.findall(r'Godot_v[0-9.]+-stable_linux\.x86_64', text)),
            job.get('runs-on'), job.get('strategy'), job.get('env', {}),
            [(s.get('shell'), s.get('if'), s.get('env', {})) for s in job.get('steps', [])
             if '--script res://' in s.get('run', '') or re.search(r'python3?\s+validation/.*run_exact\.py', s.get('run', ''))])


def transform(files: dict[str, str]) -> tuple[dict[str, str], dict]:
    out = dict(files)
    notes = []
    if PC in files:
        cfg = load_yaml(files[PC]); removed = 0
        for job in cfg.get('jobs', {}).values():
            steps = job.get('steps', [])
            if not any("unittest discover -s tests/harness" in s.get('run', '') for s in steps):
                continue
            kept = []
            for step in steps:
                command = step.get('run', '').replace('\\\n', ' ')
                tokens = command.split()
                redundant = (tokens[:3] == ['python3', '-m', 'unittest'] and len(tokens) > 3
                             and all(re.fullmatch(r'tests\.harness\.test_[A-Za-z0-9_]+', t)
                                     for t in tokens[3:]))
                if redundant:
                    removed += len(tokens[3:])
                else:
                    kept.append(step)
            job['steps'] = kept
        cfg['concurrency'] = {'group': 'project-control-${{ github.event.pull_request.number || github.ref }}',
                              'cancel-in-progress': True}
        out[PC] = dump_yaml(cfg)
        notes.append({'project_control_duplicate_module_calls_removed': removed})
    if LIVE in files:
        cfg = load_yaml(files[LIVE]); events = cfg.get('on', {})
        if not isinstance(events, dict):
            raise ValueError('LIVE_EVENTS_UNSUPPORTED')
        pr = events.get('pull_request')
        if 'pull_request' in events and (pr is None or isinstance(pr, dict)):
            pr = dict(pr or {})
            if 'paths' not in pr:
                pr['paths-ignore'] = sorted(set(pr.get('paths-ignore', [])) | {'docs/**', '**/*.md'})
            events['pull_request'] = pr
        cfg['concurrency'] = {'group': 'v0-live2-r1-targeted-windows-${{ github.event.pull_request.number || github.ref }}',
                              'cancel-in-progress': True}
        out[LIVE] = dump_yaml(cfg)
    available = [path for path in ECO if path in files]
    if available:
        winner = available[-1]; latest = load_yaml(files[winner]); compatible = True
        candidates = {path: load_yaml(files[path]) for path in available}
        for path, cfg in candidates.items():
            if cfg.get('env', {}) != latest.get('env', {}) or cfg.get('permissions', {}) != latest.get('permissions', {}):
                compatible = False
            for name, job in cfg.get('jobs', {}).items():
                target = latest.get('jobs', {}).get(name)
                if (target is None or not _invocations(job) <= _invocations(target)
                        or not _markers(job) <= _markers(target)
                        or _engine_pins(job) != _engine_pins(target)):
                    compatible = False
        if compatible:
            events = dict(latest.get('on') or {}); paths = set(); branches = set()
            broad_pr = False; broad_push = False
            for path, cfg in candidates.items():
                source = cfg.get('on') or {}
                if 'pull_request' in source:
                    pr = source.get('pull_request') or {}
                    if not pr.get('paths'):
                        broad_pr = True
                    paths.update(pr.get('paths', []))
                if 'push' in source:
                    push = source.get('push') or {}
                    if not push.get('branches'):
                        broad_push = True
                    branches.update(push.get('branches', []))
            if paths or broad_pr:
                events['pull_request'] = {} if broad_pr else {'paths': sorted(paths)}
            if branches or broad_push:
                events['push'] = {} if broad_push else {'branches': sorted(branches)}
            events['workflow_dispatch'] = None
            latest['on'] = events
            out[winner] = dump_yaml(latest)
            for path in available[:-1]:
                cfg = candidates[path]
                cfg['on'] = {'workflow_dispatch': None}
                out[path] = '# Automatic coverage is owned by ' + winner + '; manual historical replay retained.\n' + dump_yaml(cfg)
            before = sum(len(_invocations(job)) for cfg in candidates.values() for job in cfg['jobs'].values())
            after = sum(len(_invocations(job)) for job in latest['jobs'].values())
            notes.append({'eco_union': winner, 'workflow_count': len(available),
                          'static_unique_invocation_slots_before': before,
                          'static_unique_invocation_slots_after': after,
                          'runtime_execution_not_claimed': True})
        else:
            notes.append({'eco_deduplication': 'RETAINED_ORIGINAL_INCOMPATIBLE_JOB_CONTRACTS'})
    out[POLICY] = json.dumps(POLICY_VALUE, ensure_ascii=False, indent=2) + '\n'
    out[PLAN] = PLAN_TEXT
    out[MODULE] = MODULE_TEXT
    for path in DOCS:
        if path in files and '<!-- DEV-FLOW-2026-10-28-R1 -->' not in files[path]:
            out[path] = NOTICE + files[path]
    if CONTINUATION in files:
        text = files[CONTINUATION]
        if 'from .development_flow import execution_plan' not in text:
            anchor = '    mission = mission_from_state(state)\n'
            if text.count(anchor) == 1 and 'from .mission import mission_from_state\n' in text:
                text = text.replace('from .mission import mission_from_state\n',
                                    'from .mission import mission_from_state\nfrom .development_flow import execution_plan\n')
                text = text.replace(anchor, anchor + '    mission["review_execution_plan"] = execution_plan(work_order)\n')
                out[CONTINUATION] = text
            else:
                notes.append({'harness_runtime_advice': 'LEGACY_SHAPE_POLICY_DOCS_ONLY'})
    return {k: v for k, v in out.items() if files.get(k) != v}, {'revision': VERSION, 'notes': notes}


def git(*args, cwd=None, env=None, data=None, check=True):
    process = subprocess.run(['git', *args], cwd=cwd, env=env, input=data,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and process.returncode:
        raise RuntimeError(f'git {args[0]} failed: {process.stderr.decode(errors="replace")[-1600:]}')
    return process.stdout.decode().strip()


def apply_checkout(root: Path):
    existing = {path: (root/path).read_text(encoding='utf-8') for path in PATHS if (root/path).is_file()}
    changes, receipt = transform(existing)
    for path, text in changes.items():
        target = root/path; target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding='utf-8')
    receipt['changed_paths'] = sorted(changes)
    print(json.dumps(receipt, ensure_ascii=False))
    return receipt


def plan_branches(root: Path, output: Path):
    """Create only local commit objects; publish separately after inspecting the receipt."""
    refs = git('for-each-ref', '--format=%(refname) %(objectname)', 'refs/remotes/origin/', cwd=root)
    cache: dict[str, str] = {}; rows = []
    env = dict(os.environ, GIT_AUTHOR_NAME='Development Flow Migration',
               GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com',
               GIT_COMMITTER_NAME='Development Flow Migration',
               GIT_COMMITTER_EMAIL='41898282+github-actions[bot]@users.noreply.github.com')
    with tempfile.TemporaryDirectory(prefix='dws-flow-index-') as tmp:
        env['GIT_INDEX_FILE'] = str(Path(tmp)/'index')
        for line in refs.splitlines():
            ref, parent = line.split(); branch = ref.removeprefix('refs/remotes/origin/')
            if branch == 'HEAD':
                continue
            raw = git('ls-tree', '-r', parent, '--', *PATHS, cwd=root)
            entries = {}; files = {}
            for item in raw.splitlines():
                metadata, path = item.split('\t', 1); mode, kind, sha = metadata.split()
                if kind != 'blob' or mode not in {'100644','100755'}:
                    raise ValueError(f'UNSUPPORTED_MODE:{branch}:{path}')
                entries[path] = (mode, sha)
                if sha not in cache:
                    cache[sha] = subprocess.check_output(['git','cat-file','blob',sha], cwd=root).decode('utf-8')
                files[path] = cache[sha]
            changes, receipt = transform(files)
            row = {'branch': branch, 'before': parent, 'changes': sorted(changes), **receipt}
            if changes:
                git('read-tree', parent, cwd=root, env=env)
                index_lines = []
                for path, text in sorted(changes.items()):
                    sha = git('hash-object', '-w', '--stdin', cwd=root, data=text.encode('utf-8'))
                    index_lines.append(f'{entries.get(path, ("100644", ""))[0]} {sha}\t{path}\n')
                git('update-index', '--index-info', cwd=root, env=env, data=''.join(index_lines).encode())
                tree = git('write-tree', cwd=root, env=env)
                message = f'ci(control): apply {VERSION} without product changes\n\nPrevious-Head: {parent}\n'
                commit = git('commit-tree', tree, '-p', parent, cwd=root, env=env, data=message.encode())
                actual = set(git('diff-tree', '--no-commit-id','--name-only','-r',parent,commit,cwd=root).splitlines())
                if actual != set(changes) or not actual <= set(PATHS):
                    raise ValueError('ROLLOUT_SCOPE_VIOLATION')
                row.update(after=commit, tree=tree, status='PREPARED_NOT_PUBLISHED')
            else:
                row.update(after=parent, status='ALREADY_CURRENT')
            rows.append(row)
            if len(rows) % 100 == 0:
                print(f'PREPARED_BRANCHES={len(rows)}', flush=True)
    report = {'revision': VERSION, 'branch_count': len(rows), 'rows': rows}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f'ROLLOUT_MANIFEST={output}; BRANCHES={len(rows)}', flush=True)
    return report


def publish(root: Path, manifest: Path):
    """Normal batched non-force pushes. Record every outcome and verify final refs."""
    report = json.loads(manifest.read_text(encoding='utf-8'))
    if report.get('revision') != VERSION:
        raise ValueError('MANIFEST_REVISION_MISMATCH')
    def save():
        manifest.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
    def remote_heads():
        return dict((ref.removeprefix('refs/heads/'), sha)
                    for sha, ref in (x.split() for x in git('ls-remote','--heads','origin',cwd=root).splitlines()))
    pending = [row for row in report['rows'] if row['status'] == 'PREPARED_NOT_PUBLISHED']
    for offset in range(0, len(pending), 32):
        current = remote_heads(); batch = []
        for row in pending[offset:offset+32]:
            if current.get(row['branch']) != row['before']:
                row['status'] = 'REMOTE_MOVED_NOT_UPDATED'
            else:
                batch.append(row)
        save()
        if not batch:
            continue
        try:
            git('push','--atomic','origin',*[f'{r["after"]}:refs/heads/{r["branch"]}' for r in batch],cwd=root)
        except RuntimeError as exc:
            for row in batch:
                row['status'] = 'PUBLISH_REJECTED'; row['error'] = str(exc)
            save()
            raise
        observed = remote_heads()
        for row in batch:
            row['status'] = 'PUBLISHED_VERIFIED' if observed.get(row['branch']) == row['after'] else 'REMOTE_MOVED_AFTER_PUSH'
        save()
        print(f'PUBLISHED_BATCH={offset//32+1}; BRANCHES={len(batch)}',flush=True)
    statuses = {}
    for row in report['rows']:
        statuses[row['status']] = statuses.get(row['status'],0)+1
    print(json.dumps({'publication_status': statuses},ensure_ascii=False))
    if any(row['status'] not in {'PUBLISHED_VERIFIED','ALREADY_CURRENT'} for row in report['rows']):
        raise RuntimeError('ROLLOUT_INCOMPLETE_SEE_RECEIPT')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['checkout','plan','publish'])
    parser.add_argument('--root', type=Path, default=Path('.'))
    parser.add_argument('--manifest', type=Path, default=Path('artifacts/dev-flow/rollout.json'))
    args=parser.parse_args()
    if args.mode=='checkout': apply_checkout(args.root)
    elif args.mode=='plan': plan_branches(args.root,args.manifest)
    else: publish(args.root,args.manifest)

if __name__=='__main__':
    main()
