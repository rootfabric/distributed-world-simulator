"""Exact MVP2 machine evidence. No source export, Git writes or independent verdict."""
from __future__ import annotations
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
BASE = '6fd80b8dbc0cfc422c2ef9a05d2e60a4e7342b57'
MAIN = '127c732a56cc5c25d5712f24a7627ed4bb877374'
BRANCH = 'feature/v0-mvp-playable-seamless-planet-r1'
EPOCH = 'E2026-09-09-V0-MVP-R1'
WO = 'V0-MVP-R1-WO-001'
EX = f'config/control/harness/executions/{EPOCH}'
SCENE = 'res://scenes/labs/mvp/v0_mvp_two_client_shared_world.tscn'
BUILD = 'v0-mvp2-two-client-shared-world-r1'
ENGINE_SHA = {
    'linux': 'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7',
    'win32': '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5',
}
GODOT_ERRORS = re.compile(r'(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error')


def require(condition: bool, code: str) -> None:
    if not condition:
        raise RuntimeError(code)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(temp, path)


def players(observation: dict) -> dict:
    return {p['logical_player_id']: p for p in observation.get('snapshot', {}).get('players', [])}


def stable_snapshot(observation: dict) -> dict:
    """Ignore ONLY the top-level clock and the checksum that includes that clock."""
    value = copy.deepcopy(observation.get('snapshot', {}))
    value.pop('server_tick', None)
    value.pop('checksum', None)
    return value


def observation_errors(o: dict, head: str, client_id: str | None = None) -> list[str]:
    errors: list[str] = []
    def check(ok: bool, code: str) -> None:
        if not ok:
            errors.append(code)
    check(o.get('configured') is True and not o.get('stopped'), 'NOT_CONFIGURED')
    check(o.get('scene_path') == SCENE and o.get('world_id') == 'moon', 'WRONG_SCENE_WORLD')
    check(not o.get('error'), 'SCENE_ERROR')
    runtime = o.get('runtime', {})
    check(not runtime.get('last_error_code'), 'RUNTIME_ERROR')
    fp = runtime.get('network_fingerprint', {})
    check(fp.get('git_commit') == head and fp.get('world_id') == 'moon'
          and fp.get('build_id') == BUILD, 'FINGERPRINT_IDENTITY')
    records = o.get('snapshot', {}).get('players', [])
    ids = [p.get('logical_player_id') for p in records]
    check(len(ids) == 2 and set(ids) == {'a', 'b'}, 'TWO_PLAYERS_REQUIRED')
    for p in records:
        check(p.get('connected') is True and p.get('player_entity_id') == 'player/' + str(p.get('logical_player_id'))
              and p.get('ownership_epoch', 0) >= 1, 'PLAYER_IDENTITY')
    item = o.get('item_graph_snapshot', {})
    check(bool(item) and len(item.get('checksum', '')) == 64, 'ITEM_SNAPSHOT_REQUIRED')
    surface = o.get('surface', {})
    check(surface.get('configured') is True and len(surface.get('bootstrap_hash', '')) == 64,
          'BOOTSTRAP_REQUIRED')
    check(surface.get('canonical_state_owned') is False
          and surface.get('mutable_matter_store_retained') is False, 'CLIENT_MATTER_AUTHORITY')
    if client_id is None:
        check(o.get('role') == 'dedicated-server' and o.get('server_runtime_present') is True
              and o.get('client_runtime_present') is False, 'SERVER_ROLE')
        check(runtime.get('connected_peer_count') == 2
              and set(runtime.get('peer_to_player', {}).values()) == {'a', 'b'}, 'SERVER_PEER_MAP')
    else:
        check(o.get('role') == 'game-client' and o.get('player_id') == client_id
              and o.get('server_runtime_present') is False and o.get('client_runtime_present') is True, 'CLIENT_ROLE')
        check(runtime.get('joined') is True and runtime.get('compatibility_handshake', {}).get('verified') is True,
              'HANDSHAKE_JOIN_REQUIRED')
        check(runtime.get('server_disconnects') == 0, 'UNEXPECTED_DISCONNECT')
        check(o.get('local_body_visible') is True and bool(o.get('active_camera')), 'LOCAL_VIEW_REQUIRED')
        check(surface.get('mesh_count', 0) > 0, 'SURFACE_MESH_REQUIRED')
        remote_id = 'b' if client_id == 'a' else 'a'
        views = o.get('remote_presenters', {})
        check(set(views) == {remote_id}, 'ONE_REMOTE_REQUIRED')
        for view in views.values():
            check(view.get('input_authority') is False, 'REMOTE_INPUT_AUTHORITY')
            check(view.get('body_visible_in_tree') is True
                  and view.get('inside_camera_frustum') is True, 'REMOTE_VISIBILITY')
    return errors


def shared_errors(server: dict, a: dict, b: dict, head: str) -> list[str]:
    errors = (['server:' + e for e in observation_errors(server, head)]
              + ['a:' + e for e in observation_errors(a, head, 'a')]
              + ['b:' + e for e in observation_errors(b, head, 'b')])
    if not (stable_snapshot(server) == stable_snapshot(a) == stable_snapshot(b)):
        errors.append('SHARED_GAMEPLAY_MISMATCH')
    if not (server.get('item_graph_snapshot') == a.get('item_graph_snapshot') == b.get('item_graph_snapshot')):
        errors.append('SHARED_ITEM_GRAPH_MISMATCH')
    surfaces = [o.get('surface', {}) for o in (server, a, b)]
    for key in ('bootstrap_hash', 'descriptor'):
        if not (surfaces[0].get(key) == surfaces[1].get(key) == surfaces[2].get(key)):
            errors.append('SHARED_SURFACE_MISMATCH:' + key)
    if len({o.get('process_id') for o in (server, a, b)}) != 3:
        errors.append('PROCESS_ISOLATION')
    if len({o.get('user_data_dir') for o in (server, a, b)}) != 3:
        errors.append('USER_DATA_ISOLATION')
    sessions = [o.get('runtime', {}).get('transport_session_id') for o in (a, b)]
    if not all(sessions) or len(set(sessions)) != 2:
        errors.append('SESSION_ISOLATION')
    fingerprints = [o.get('runtime', {}).get('network_fingerprint') for o in (server, a, b)]
    if not fingerprints[0] or not (fingerprints[0] == fingerprints[1] == fingerprints[2]):
        errors.append('SHARED_FINGERPRINT_MISMATCH')
    return errors


class Run:
    def __init__(self, engine: Path, out: Path, runtime_only: bool):
        self.engine, self.out, self.runtime_only = engine.resolve(), out, runtime_only
        self.env = dict(os.environ, PYTHONUTF8='1', BREAKPOINT_RUNTIME_DISABLED='1',
                        PLANET_SIMULATOR_INVENTORY_PROFILE='planet_default',
                        PYTHONPATH=str(ROOT / 'scripts') + os.pathsep + str(ROOT))
        self.result = {'schema': 'distributed_world_simulator.mvp2_exact_result.v1',
                       'passed': False, 'errors': [], 'commands': [], 'checks': {},
                       'independent_verdict': False, 'predicate_verified': False,
                       'world_core_regression': 'NOT_RUN_THIS_LEAF',
                       'control_scope': 'NOT_REQUESTED' if runtime_only else 'FULL_HARNESS_AND_PC0',
                       'started_at_utc': datetime.now(timezone.utc).isoformat()}
        self.children: dict[str, dict] = {}
        self.head = ''
        self.nonce = uuid.uuid4().hex
        self.port = 26000 + (int(self.nonce[:4], 16) % 16000)

    def git(self, *args: str) -> str:
        return subprocess.check_output(['git', *args], cwd=ROOT, env=self.env).decode('utf-8').strip()

    def command(self, name: str, argv: list[str], expected: int = 0, timeout: int = 900, godot: bool = False) -> str:
        path = self.out / (name + '.log')
        started = time.monotonic()
        with path.open('w', encoding='utf-8') as log:
            proc = subprocess.run(argv, cwd=ROOT, env=self.env, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        self.result['commands'].append({'name': name, 'argv': argv, 'exit_code': proc.returncode,
                                       'expected_exit_code': expected, 'seconds': round(time.monotonic() - started, 3),
                                       'log': path.name, 'sha256': sha(path)})
        text = path.read_text(encoding='utf-8', errors='replace')
        require(proc.returncode == expected, f'{name}:EXIT:{proc.returncode}')
        require(not godot or not GODOT_ERRORS.search(text), f'{name}:GODOT_ERROR')
        return text

    def spawn(self, name: str, role: str, player: str, token: str, graphical: bool) -> None:
        folder = self.out / name
        folder.mkdir()
        env = dict(self.env, DWS_MVP2_FIXTURE_CONTROL=str(folder / 'control.json'),
                   DWS_MVP2_FIXTURE_OUTPUT=str(folder / 'observation.json'),
                   DWS_MVP2_FIXTURE_SCREENSHOT=str(folder / 'viewport.png'),
                   DWS_MVP2_FIXTURE_NONCE=self.nonce,
                   XDG_DATA_HOME=str(folder / 'user-data'), APPDATA=str(folder / 'user-data'))
        args = [str(self.engine), '--path', str(ROOT), '--rendering-method', 'gl_compatibility',
                '--audio-driver', 'Dummy', '--resolution', '1280x720']
        if not graphical:
            args.append('--headless')
        args += ['--script', 'res://tests/integration/test_v0_mvp_two_client_process.gd', '--',
                 '--role=' + role, '--world=moon', '--player-identity=' + player,
                 '--server-address=127.0.0.1', '--server-port=' + str(self.port),
                 '--network-session-token=' + token, '--network-build-id=' + BUILD,
                 '--network-git-commit=' + self.head, '--connect-timeout-ms=15000']
        log = (folder / 'process.log').open('w', encoding='utf-8')
        process = subprocess.Popen(args, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        self.children[name] = dict(process=process, log=log, folder=folder, sequence=0,
                                   args=args, graphical=graphical, stopped=False)
        self.result.setdefault('processes', {})[name] = {'pid': process.pid, 'argv': args,
                                                       'graphical_requested': graphical}

    def read(self, name: str) -> dict:
        child = self.children[name]
        try:
            value = json.loads((child['folder'] / 'observation.json').read_text(encoding='utf-8'))
        except (FileNotFoundError, json.JSONDecodeError):
            return {}
        require(value.get('nonce') == self.nonce and value.get('process_id') == child['process'].pid,
                'STALE_OR_FOREIGN_PROCESS_REPORT:' + name)
        require(value.get('state') != 'FAILED', 'PROCESS_FAILED:' + name + ':' + str(value.get('extra')))
        return value

    def observation(self, name: str) -> dict:
        return self.read(name).get('observation', {})

    def wait(self, label: str, predicate, timeout: float = 30) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for name, child in self.children.items():
                require(child['stopped'] or child['process'].poll() is None,
                        f'UNEXPECTED_PROCESS_EXIT:{name}:{child["process"].poll()}')
            if predicate():
                return
            time.sleep(0.1)
        raise RuntimeError('TIMEOUT:' + label)

    def send(self, name: str, kind: str, **values) -> None:
        child = self.children[name]
        child['sequence'] += 1
        write(child['folder'] / 'control.json', dict(nonce=self.nonce, sequence=child['sequence'], kind=kind, **values))

    def witness(self, name: str) -> dict:
        value = {key: self.observation(key) for key in ('server', 'a', 'b')}
        write(self.out / ('witness-' + name + '.json'), value)
        return value

    def converge(self, label: str) -> dict:
        self.wait(label, lambda: not shared_errors(self.observation('server'), self.observation('a'),
                                                   self.observation('b'), self.head))
        value = self.witness(label)
        require(not shared_errors(value['server'], value['a'], value['b'], self.head), 'UNSTABLE_WITNESS:' + label)
        return value

    def stop(self, name: str) -> None:
        child = self.children[name]
        self.send(name, 'stop')
        code = child['process'].wait(timeout=12)
        child['stopped'] = True
        child['log'].close()
        text = (child['folder'] / 'process.log').read_text(encoding='utf-8', errors='replace')
        self.result['processes'][name]['exit_code'] = code
        require(code == 0 and not GODOT_ERRORS.search(text), f'PROCESS_STOP_OR_GODOT_ERROR:{name}:{code}')
        report = self.read(name)
        require(report.get('state') == 'STOPPED' and report.get('extra', {}).get('stop_result', {}).get('success') is True,
                'UNCLEAN_SESSION_STOP:' + name)

    def workload(self) -> None:
        token = 'session-id/mvp2-' + self.nonce
        self.spawn('server', 'dedicated-server', 'server', token, False)
        self.wait('server-ready', lambda: self.observation('server').get('configured') is True)
        self.spawn('a', 'game-client', 'a', token, True)
        self.wait('a-joined', lambda: self.observation('a').get('runtime', {}).get('joined') is True)
        single = self.observation('a')
        require('TWO_PLAYERS_REQUIRED' in observation_errors(single, self.head, 'a'), 'SINGLE_CLIENT_FALSE_PASS')
        write(self.out / 'negative-single-client.json', single)
        self.result['checks']['single_client_rejected'] = True
        self.spawn('b', 'game-client', 'b', token, True)
        before = self.converge('initial')
        for actor, action in [('a', 'mvp2_right'), ('b', 'mvp2_back')]:
            self.send(actor, 'keys', actions=[action])
            self.wait(actor + '-keys-ack', lambda: self.read(actor).get('control_sequence') == self.children[actor]['sequence'])
            time.sleep(0.25)
            self.send(actor, 'neutral')
            def moved() -> bool:
                records = players(self.observation('server'))
                if actor not in records:
                    return False
                p, q = records[actor]['position'], players(before['server'])[actor]['position']
                return sum((float(p[k]) - float(q[k])) ** 2 for k in ('x', 'z')) > 0.0025
            self.wait(actor + '-server-confirmed-movement', moved)
            after = self.converge('after-' + actor)
            require(players(after['server'])[actor].get('last_input_sequence', 0) > 0, 'NO_INPUT_ACK:' + actor)
            other = 'b' if actor == 'a' else 'a'
            p, q = players(before['server'])[other]['position'], players(after['server'])[other]['position']
            require(sum((float(p[k]) - float(q[k])) ** 2 for k in ('x', 'z')) < 0.04, 'FOREIGN_PLAYER_MOVED:' + actor)
            self.result['checks'][actor + '_movement_replicated_to_both'] = True
            before = after
        self.send('a', 'hide_remote')
        self.wait('hidden-remote', lambda: 'REMOTE_VISIBILITY' in observation_errors(self.observation('a'), self.head, 'a'))
        write(self.out / 'negative-hidden-remote.json', self.observation('a'))
        self.result['checks']['hidden_remote_rejected'] = True
        self.send('a', 'restore_remote')
        final = self.converge('restored')
        tampered = copy.deepcopy(final['b'])
        tampered['snapshot']['players'][0]['position']['x'] += 1.0
        require('SHARED_GAMEPLAY_MISMATCH' in shared_errors(final['server'], final['a'], tampered, self.head),
                'TAMPERED_STATE_FALSE_PASS')
        self.result['checks']['tampered_state_rejected'] = True
        for name in ('a', 'b'):
            self.send(name, 'capture')
            self.wait(name + '-capture', lambda: bool(self.read(name).get('capture')))
            capture = self.read(name)['capture']
            png = self.children[name]['folder'] / 'viewport.png'
            require(sha(png) == capture['sha256'] and capture['width'] >= 640 and capture['height'] >= 360,
                    'CAPTURE_IDENTITY:' + name)
            require(self.observation(name).get('display_server', '').lower() not in ('headless', 'dummy', ''),
                    'CLIENT_NOT_GRAPHICAL:' + name)
        self.witness('graphical')
        self.spawn('foreign', 'game-client', 'foreign', token + '-foreign', False)
        self.wait('foreign-session-rejected', lambda: bool(self.observation('foreign').get('error')))
        bad = self.observation('foreign')
        require(bad.get('runtime', {}).get('joined') is False
                and bad.get('runtime', {}).get('compatibility_handshake', {}).get('rejections', 0) > 0,
                'FOREIGN_SESSION_NOT_REJECTED_BY_HANDSHAKE')
        write(self.out / 'negative-foreign-session.json', bad)
        self.result['checks']['foreign_session_rejected_before_join'] = True
        self.stop('foreign')
        self.converge('final')
        for name in ('a', 'b', 'server'):
            self.stop(name)
        self.result['checks']['all_owned_processes_stopped_cleanly'] = True

    def execute(self) -> int:
        try:
            self.head = self.git('rev-parse', 'HEAD')
            self.result.update(subject_head_sha=self.head, subject_tree_sha=self.git('rev-parse', 'HEAD^{tree}'),
                               main_head=self.git('rev-parse', 'origin/main'),
                               tracked_before=self.git('status', '--porcelain', '--untracked-files=no'))
            require(self.head == os.environ.get('EXPECTED_HEAD', self.head), 'HEAD_MISMATCH')
            require(self.result['main_head'] == MAIN, 'MAIN_DRIFT_REQUIRES_EPOCH_AUDIT')
            require(not self.result['tracked_before'], 'TRACKED_DIRTY_BEFORE')
            require(sha(self.engine) == ENGINE_SHA.get(sys.platform), 'GODOT_BINARY_HASH_MISMATCH')
            self.result['engine_sha256'] = sha(self.engine)
            self.git('merge-base', '--is-ancestor', BASE, self.head)
            protected = ['scripts/network', 'scripts/simulation', 'scripts/runtime/networked_gameplay/m3',
                         'scripts/runtime/networked_gameplay/m4', 'scripts/runtime/networked_gameplay/p7',
                         'scripts/runtime/networked_gameplay/sm1', 'config/architecture',
                         'config/control/harness/acceptance', 'project.godot', 'main.tscn',
                         'scenes/labs/mvp/v0_mvp_shared_graphical_scene.tscn',
                         'scripts/runtime/networked_gameplay/mvp/v0_mvp_shared_graphical_scene.gd']
            require(not self.git('diff', '--name-only', BASE, self.head, '--', *protected), 'PROTECTED_SCOPE_CHANGED')
            old = set(self.git('ls-tree', '-r', BASE, '--', EX + '/events').splitlines())
            new = set(self.git('ls-tree', '-r', self.head, '--', EX + '/events').splitlines())
            require(old <= new, 'HISTORICAL_EVENT_CHANGED')
            self.command('diff-check', ['git', 'diff', '--check', BASE, self.head])
            self.command('evidence-consumer-tests', [sys.executable, '-m', 'unittest', 'discover', '-s',
                         'tests/integration', '-p', 'test_v0_mvp_two_client_evidence.py', '-v'])
            if not self.runtime_only:
                self.command('full-harness', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tests/harness', '-p', 'test_*.py', '-v'])
                self.command('pc0-standard', [sys.executable, 'scripts/control/project_control.py', '--no-fetch'])
                self.command('pc0-directional', [sys.executable, 'scripts/control/project_control_directional_watch.py'])
                for src, dest in [('project-control-report.json', 'pc0-standard.json'), ('directional-watch-report.json', 'pc0-directional.json')]:
                    shutil.copyfile(ROOT / 'artifacts/control' / src, self.out / dest)
                standard = json.loads((self.out / 'pc0-standard.json').read_text())
                directional = json.loads((self.out / 'pc0-directional.json').read_text())
                require(standard['overall_health'] in ('GREEN', 'YELLOW') and standard['cross_branch_overlaps'] == [], 'PC0_BLOCKED')
                require(directional['overall_health'] in ('GREEN', 'YELLOW'), 'DIRECTIONAL_BLOCKED')
                require(not any(f.get('level') == 'RED' and f.get('global_blocking') is not False for f in directional['findings']), 'DIRECTIONAL_BLOCKING_RED')
            version = self.command('godot-version', [str(self.engine), '--version'], godot=True)
            require('4.7.1.stable.double.custom_build.a13da4feb' in version, 'GODOT_VERSION_MISMATCH')
            base = [str(self.engine), '--headless', '--path', str(ROOT)]
            self.command('godot-import', base + ['--editor', '--import'], godot=True)
            self.command('mvp1-regression', base + ['--script', 'res://tests/runtime/test_v0_mvp_shared_graphical_scene.gd'], godot=True)
            focused = self.command('mvp2-focused', base + ['--script', 'res://tests/runtime/test_v0_mvp_two_client_shared_world.gd'], godot=True)
            require('MVP2 focused: PASS (' in focused, 'FOCUSED_PASS_MARKER_MISSING')
            self.workload()
            self.result['runtime_workload_pass'] = True
            self.result['passed'] = True
        except Exception as exc:
            self.result['errors'].append(type(exc).__name__ + ':' + str(exc))
        finally:
            for name, child in self.children.items():
                if child['process'].poll() is None:
                    try:
                        self.stop(name)
                    except Exception as exc:
                        self.result['passed'] = False
                        self.result['errors'].append('CLEANUP:' + name + ':' + str(exc))
                        child['process'].terminate()
                        try:
                            child['process'].wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            child['process'].kill()
                            child['process'].wait(timeout=5)
                child['log'].close()
            self.result['tracked_after'] = self.git('status', '--porcelain', '--untracked-files=no')
            if self.result['tracked_after']:
                self.result['passed'] = False
                self.result['errors'].append('TRACKED_DIRTY_AFTER')
            self.result['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
            write(self.out / 'result.json', self.result)
            run_id = os.environ.get('GITHUB_RUN_ID', 'local-' + self.nonce)
            sink = f'{EX}/evidence/MVP2-NATIVE-{self.head[:12]}-{run_id}'
            files = sorted(p for p in self.out.rglob('*') if p.is_file() and 'user-data' not in p.parts and p.name != 'manifest.v1.json')
            manifest = {
                'schema': 'distributed_world_simulator.harness_machine_evidence_manifest.v1',
                'work_order_id': WO, 'project_epoch': EPOCH, 'subject_head_sha': self.head,
                'subject_tree_sha': self.result.get('subject_tree_sha'),
                'runner_id': os.environ.get('RUNNER_NAME', 'local-' + sys.platform), 'run_id': run_id,
                'tracked_checkout_clean_before': self.result.get('tracked_before') == '',
                'tracked_checkout_clean_after': self.result['tracked_after'] == '',
                'artifacts': [dict(path=sink + '/' + p.relative_to(self.out).as_posix(),
                                   sha256=sha(p), run_id=run_id, subject_head_sha=self.head,
                                   archive_member=p.relative_to(self.out).as_posix()) for p in files],
                'commands': [dict(command=subprocess.list2cmdline(c['argv']), exit_code=c['exit_code'],
                                  expected_exit_code=c['expected_exit_code'], log_path=sink + '/' + c['log']) for c in self.result['commands']],
                'intended_manifest_path': sink + '/manifest.v1.json',
                'publication_required_before_native_review_consumption': True,
                'independent_verdict': False,
                'runner': {k: os.environ.get(k, '') for k in ['GITHUB_REPOSITORY', 'GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'RUNNER_NAME', 'RUNNER_OS']},
            }
            write(self.out / 'manifest.v1.json', manifest)
        print(json.dumps({'passed': self.result['passed'], 'errors': self.result['errors'], 'output': str(self.out)}))
        return 0 if self.result['passed'] else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', default=os.environ.get('GODOT_BIN'))
    parser.add_argument('--runtime-only', action='store_true', help='Do not claim full Harness/PC0 evidence.')
    args = parser.parse_args()
    require(bool(args.engine), 'GODOT_BIN_REQUIRED')
    out = ROOT / 'artifacts/mvp2-exact'
    out.mkdir(parents=True, exist_ok=False)
    return Run(Path(args.engine), out, args.runtime_only).execute()


if __name__ == '__main__':
    raise SystemExit(main())
