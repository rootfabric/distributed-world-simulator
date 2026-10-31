"""Real ENet two-player gameplay, seam, reconnect and graceful process recovery."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import socket
import subprocess
import time
import traceback


def require(condition, code):
    if not condition:
        raise AssertionError(code)


def ore(state, player):
    return sum(i['quantity'] for i in state['items']['items']
               if i['definition_id'] == 'item/ore' and
               i['location'].get('kind') == 'INVENTORY' and
               i['location'].get('player_id') == player)


def remaining(state):
    return next(n['remaining_units'] for n in state['resource']['nodes']
                if n['resource_node_id'] == 'resource/earth/ore-demo/1')


def durable(state):
    # Bundle session metadata may change on reconnect; compare canonical construct.
    return {k: state[k]['checksum'] for k in ('items', 'resource')} | {
        'construct': state['outpost']['construct_checksum'],
        'stages': state['outpost']['completed_stage_count']}


def verify_world(states, units, a_ore, b_ore, stages):
    for role, state in states.items():
        require(state['report']['connection_state'] == 'CONNECTED', role + ': disconnected')
        require(remaining(state) == units, role + ': resource count')
        require(ore(state, 'a') == a_ore and ore(state, 'b') == b_ore, role + ': inventory count')
        total_ore = sum(i['quantity'] for i in state['items']['items'] if i['definition_id'] == 'item/ore')
        # The accepted sandbox also seeds eight loose ore units; this scenario
        # must use the mined output, leaving that independent stack untouched.
        seeded = next(i for i in state['items']['items'] if i['item_id'] == 'item/shared/ore/1')
        require(seeded['quantity'] == 8 and seeded['location']['kind'] == 'WORLD', role + ': seeded ore changed')
        require(total_ore + units + (0, 2, 6, 8)[stages] == 16, role + ': material conservation')
        require(state['outpost']['completed_stage_count'] == stages, role + ': construction stage')
        for key in ('items', 'resource', 'construction'):
            require(len(state[key].get('checksum', '')) == 64, role + ': missing ' + key)
        require(len(state['outpost']['construct_checksum']) == (64 if stages else 0), role + ': construct existence')
    require(durable(states['a']) == durable(states['b']), 'replicas disagree')


class SharedGameplayCheck:
    def __init__(self, args):
        self.args, self.project = args, args.project.resolve()
        output = args.output.resolve()
        workspace_artifacts = Path('C:/distributed-world-simulator/artifacts').resolve()
        require(output.is_relative_to(workspace_artifacts), 'OUTPUT_OUTSIDE_WORKSPACE_ARTIFACTS')
        self.root = output / (time.strftime('%Y%m%d-%H%M%S') + '-' + str(os.getpid()))
        self.root.mkdir(parents=True)
        self.head = self.git('rev-parse', 'HEAD').strip()
        self.profile = json.loads((self.project / 'config/release/playtest-r1.json').read_text())
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(('127.0.0.1', 0))
            self.port = sock.getsockname()[1]
        self.processes, self.logs, self.commands = {}, [], []
        self.report = {'schema': 'dws.shared_gameplay_check.v1', 'result': 'RUNNING',
                       'head': self.head, 'tree': self.git('rev-parse', 'HEAD^{tree}').strip(),
                       'profile': self.profile['id'], 'phases': [], 'inputs': {},
                       'limitations': ['localhost product seam; not multi-host',
                                       'graceful restart; not crash recovery',
                                       'headless runtime clients; no GUI acceptance']}
        for path in (args.godot, Path(__file__), self.project / 'tools/runtime/playtest_r1_shared_gameplay_client.gd',
                     self.project / 'config/release/playtest-r1.json'):
            self.report['inputs'][str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.save('report.json', self.report)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.project), *args], text=True)

    def save(self, name, value):
        path = self.root / name
        tmp = path.with_suffix(path.suffix + '.tmp')
        tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
        os.replace(tmp, path)

    def wait(self, name, predicate, timeout=35):
        start, last = time.monotonic(), ''
        while time.monotonic() - start < timeout:
            for role in ('a', 'b'):
                if role in self.processes and self.processes[role].poll() is not None:
                    raise RuntimeError(role + ' process exited: ' + str(self.processes[role].returncode))
            try:
                result = predicate()
                if result:
                    self.report['phases'].append({'name': name, 'seconds': time.monotonic() - start})
                    self.save('report.json', self.report)
                    print(name, 'OK', flush=True)
                    return result
            except (OSError, json.JSONDecodeError, KeyError, StopIteration) as error:
                last = str(error)
            time.sleep(.1)
        raise RuntimeError(name + ' TIMEOUT ' + last)

    def state(self, role):
        path = self.root / role / 'state.json'
        require(time.time() - path.stat().st_mtime < 5, role + ': stale client state')
        state = json.loads(path.read_text(encoding='utf-8'))
        require(state['pid'] == self.processes[role].pid, role + ': wrong state PID')
        require(not state['movement_error'], role + ': movement rejected ' + str(state['movement_error']))
        return state

    def rpc(self, role, method, params=None, operation_id='', allowed_error=None):
        operation_id = operation_id or 'operation/shared-gameplay/' + role + '/' + str(len(self.commands) + 1)
        # This explicit pre-admission response proves no mutation was submitted.
        # Retry the same operation, retaining every attempt in commands.json.
        for attempt in range(20):
            result = self._rpc_once(role, method, params, operation_id)
            if result.get('error_code') == 'P1A_WAIT_PRIOR_PERIODIC':
                time.sleep(.1)
                continue
            require(result.get('success') or (allowed_error is not None and
                    result.get('error_code') == allowed_error), str(result))
            return result
        raise RuntimeError('PRE_ADMISSION_RETRY_EXHAUSTED ' + operation_id)

    def _rpc_once(self, role, method, params, operation_id):
        request_id = str(len(self.commands) + 1)
        request = {'id': request_id, 'method': method, 'params': params or {},
                   'operation_id': operation_id or 'operation/shared-gameplay/' + role + '/' + request_id}
        self.commands.append({'role': role, 'request': request})
        self.save('commands.json', self.commands)
        self.save(role + '/request.json', request)
        def received():
            reply = json.loads((self.root / role / 'reply.json').read_text(encoding='utf-8'))
            return reply if reply['id'] == request_id else False
        reply = self.wait(role + ':' + method, received)
        self.commands[-1]['reply'] = reply
        self.save('commands.json', self.commands)
        return reply['result']

    def item(self, role, command, **payload):
        return self.rpc(role, 'item', {'command': command, 'payload': payload})

    def spawn(self, role):
        folder = self.root / role
        folder.mkdir()
        server = role.startswith('server')
        env = {k: v for k, v in os.environ.items() if not k.startswith('DWS_NET_')}
        env.update(BREAKPOINT_RUNTIME_DISABLED='1', APPDATA=str(folder), LOCALAPPDATA=str(folder))
        env.update(self.profile['server_environment' if server else 'client_environment'])
        env.update({k: '0' for k in self.profile['disabled_environment']})
        argv = [str(self.args.godot), '--headless', '--path', str(self.project), '--max-fps', '60']
        if server:
            argv += ['--', '--network-mvp', '--world=earth', '--role=dedicated-server',
                     '--server-address=127.0.0.1', '--server-port=' + str(self.port),
                     '--network-build-id=' + self.profile['network_build_id'],
                     '--network-git-commit=' + self.head, '--network-debug',
                     '--node-id=shared-gameplay-server', '--product-seam',
                     '--persistence-root=' + str(self.root / 'world')]
            if role == 'server':
                argv += ['--shutdown-after-ms=' + str(self.args.restart_after_seconds * 1000)]
        else:
            config = {'folder': str(folder), 'host': '127.0.0.1', 'port': self.port,
                      'logical_player_id': role, 'connect_timeout_ms': 30000,
                      'command_timeout_ms': 10000, 'automated_acceptance': False,
                      'playable_sandbox': True, 'world_id': 'earth', 'debug_logging': True,
                      'network_build_id': self.profile['network_build_id'], 'network_git_commit': self.head}
            self.save(role + '/config.json', config)
            argv += ['--script', 'res://tools/runtime/playtest_r1_shared_gameplay_client.gd',
                     '--', '--driver-config=' + str(folder / 'config.json')]
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
        log = (folder / 'runtime.log').open('w', encoding='utf-8')
        self.logs.append(log)
        self.processes[role] = subprocess.Popen(argv, cwd=self.project, env=env, startupinfo=startup,
                                                stdout=log, stderr=subprocess.STDOUT)
        self.save('processes.json', {k: {'pid': v.pid} for k, v in self.processes.items()})

    def ready(self, role):
        state = self.state(role)
        return (state['report']['connection_state'] == 'CONNECTED' and state['resource'].get('nodes')
                and len(state['items'].get('checksum', '')) == 64 and state['outpost']['ready'])

    def checkpoint(self, label, units, a_ore, b_ore, stages, expected=None):
        def converged():
            states = {r: self.state(r) for r in ('a', 'b')}
            try:
                verify_world(states, units, a_ore, b_ore, stages)
                if expected is not None:
                    require(durable(states['a']) == expected, label + ': persisted state changed')
            except AssertionError as error:
                self.report['last_world_mismatch'] = str(error)
                return False
            return states
        states = self.wait(label, converged)
        self.save(label + '.json', states)
        for role, state in states.items():
            require(state['report']['player_entity_id'] == self.identities[role], role + ': entity changed')
        return states

    def move(self, role, x, z):
        self.rpc(role, 'move', {'x': x, 'z': z})
        def arrived():
            state = self.state(role)
            p = state['player']['position']
            return not state['moving'] and math.hypot(p['x'] - x, p['z'] - z) < .7
        self.wait(role + ':arrived', arrived)

    def approach_resource(self, role):
        target = self.state(role)['resource_target']
        self.move(role, target['x'], target['z'])

    def roundtrip(self, role):
        before = self.state(role)
        epoch = before['report']['ownership_epoch']
        z = before['player']['position']['z']
        self.move(role, 14, z)
        self.wait(role + ':secondary', lambda: self.state(role)['seam']['region_id'] == 'region/user1/b')
        self.save(role + '-secondary.json', self.state(role))
        self.move(role, -2, z)
        after = self.wait(role + ':roundtrip', lambda: self.state(role)
                          if self.state(role)['seam']['roundtrips'] > before['seam']['roundtrips'] else False)
        require(after['seam']['region_id'] == 'region/user1/a', 'wrong return region')
        require(after['report']['ownership_epoch'] == epoch, 'seam changed ownership epoch')
        require(after['seam']['crossings'] >= before['seam']['crossings'] + 2, 'crossings missing')

    def run(self):
        started = time.monotonic()
        try:
            require(not self.args.expected_head or self.head == self.args.expected_head, 'EXPECTED_HEAD_MISMATCH')
            require(not self.git('status', '--porcelain', '--untracked-files=no').strip(), 'TRACKED_WORKTREE_DIRTY')
            self.spawn('server')
            self.wait('server-ready', lambda: '"event":"node_ready"' in
                      (self.root / 'server/runtime.log').read_text(errors='replace'))
            for role in ('a', 'b'):
                self.spawn(role)
                self.wait(role + ':ready', lambda r=role: self.ready(r))
            self.identities = {r: self.state(r)['report']['player_entity_id'] for r in ('a', 'b')}
            require(all(self.identities.values()) and self.identities['a'] != self.identities['b'], 'PLAYER_IDENTITIES_INVALID')
            self.checkpoint('initial', 8, 0, 0, 0)
            self.approach_resource('a')
            self.item('a', 'item.equip', item_id='item/player/a/p5-mining-tool', slot_id='tool/main')
            self.rpc('a', 'mine', {'quantity': 3}, 'operation/shared-gameplay/mine-first')
            mined = self.checkpoint('mined', 5, 3, 0, 0)
            self.rpc('a', 'mine', {'quantity': 3}, 'operation/shared-gameplay/mine-first')
            self.checkpoint('mine-replay', 5, 3, 0, 0, durable(mined['a']))
            ore_ids = [i['item_id'] for i in mined['a']['items']['items'] if
                       i['definition_id'] == 'item/ore' and i['location'].get('player_id') == 'a']
            require(len(ore_ids) == 1, 'expected one mined stack')
            for role in ('a', 'b'):
                self.move(role, 3, -2)
                self.item(role, 'container.open', container_id='container/shared/crate/1')
            self.item('a', 'item.transfer', item_id=ore_ids[0], quantity=-1,
                      target_container_id='container/shared/crate/1', target_slot_index=-1, target_item_id='')
            self.checkpoint('stored', 5, 0, 0, 0)
            stored = self.state('b')['items']['items']
            require(any(i['item_id'] == ore_ids[0] and i['quantity'] == 3 and
                        i['location'].get('container_id') == 'container/shared/crate/1' for i in stored), 'crate lost ore')
            self.item('b', 'item.transfer', item_id=ore_ids[0], quantity=-1,
                      target_container_id='inventory/b', target_slot_index=-1, target_item_id='')
            self.checkpoint('received', 5, 0, 3, 0)
            for role in ('a', 'b'):
                self.item(role, 'container.close', container_id='container/shared/crate/1')
            pre_build = self.checkpoint('before-foundation', 5, 0, 3, 0)
            build = self.rpc('b', 'build', allowed_error='M3_CONSTRUCTION_DURABILITY_CONTRACT_REQUIRED')
            blocked = not build.get('success')
            self.report['blocked_checks'] = ['construction', 'construction-recovery', 'continued-construction'] if blocked else []
            self.report['construction_error'] = build.get('error_code', '')
            stage, b_quantity = (0, 3) if blocked else (1, 1)
            built = self.checkpoint('foundation-rejected' if blocked else 'foundation', 5, 0, b_quantity, stage,
                                    durable(pre_build['a']) if blocked else None)
            preserved = durable(built['a'])
            for role in ('a', 'b'):
                self.roundtrip(role)
                self.checkpoint('after-seam-' + role, 5, 0, b_quantity, stage, preserved)
            before = self.state('b')['report']
            self.rpc('b', 'reconnect')
            self.wait('b:rejoined', lambda: self.ready('b') and
                      self.state('b')['report']['ownership_epoch'] > before['ownership_epoch'] and
                      self.state('b')['report']['transport_session_id'] != before['transport_session_id'])
            pre_restart = self.checkpoint('reconnected', 5, 0, b_quantity, stage, preserved)
            require(self.processes['server'].poll() is None, 'SERVER_STOPPED_BEFORE_RESTART_STAGE')
            print('Waiting for scheduled graceful server shutdown', flush=True)
            self.wait('server-stopped', lambda: self.processes['server'].poll() is not None,
                      self.args.restart_after_seconds + 15)
            require(self.processes['server'].returncode == 0, 'UNCLEAN_SERVER_EXIT')
            self.spawn('server-recovered')
            require(self.processes['server'].pid != self.processes['server-recovered'].pid, 'SERVER_PID_REUSED')
            self.wait('recovered-server-ready', lambda: '"event":"node_ready"' in
                      (self.root / 'server-recovered/runtime.log').read_text(errors='replace'))
            for role in ('a', 'b'):
                self.wait(role + ':recovered', lambda r=role: self.ready(r) and
                          self.state(r)['report']['server_disconnects'] > pre_restart[r]['report']['server_disconnects'] and
                          self.state(r)['report']['ownership_epoch'] > pre_restart[r]['report']['ownership_epoch'], timeout=60)
            self.checkpoint('recovered', 5, 0, b_quantity, stage, preserved)
            self.approach_resource('a')
            self.rpc('a', 'mine', {'quantity': 4})
            self.checkpoint('recovery-mine', 1, 4, b_quantity, stage)
            if not blocked:
                self.rpc('a', 'build')
                self.checkpoint('walls', 1, 0, 1, 2)
            self.approach_resource('b')
            self.item('b', 'item.equip', item_id='item/player/b/p5-mining-tool', slot_id='tool/main')
            self.rpc('b', 'mine', {'quantity': 1})
            self.checkpoint('last-ore', 0, 4 if blocked else 0, b_quantity + 1, 0 if blocked else 2)
            if blocked:
                self.report['executed_gameplay_checks'] = 'PASS'
                raise AssertionError('FULL_SCENARIO_BLOCKED: M3_CONSTRUCTION_DURABILITY_CONTRACT_REQUIRED')
            self.rpc('b', 'build')
            final = self.checkpoint('complete', 0, 0, 0, 3)
            require(all(s['outpost']['complete'] for s in final.values()), 'OUTPOST_NOT_COMPLETE')
            self.report['result'] = 'PASS'
        except Exception as error:
            self.report.update(result='FAIL', error=str(error), traceback=traceback.format_exc())
            print(traceback.format_exc(), flush=True)
        finally:
            for role in ('a', 'b'):
                if role in self.processes and self.processes[role].poll() is None:
                    try:
                        self.rpc(role, 'quit')
                    except Exception:
                        pass
            for process in self.processes.values():
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=8)
            for log in self.logs:
                log.close()
            self.report['processes'] = {k: {'pid': p.pid, 'exit_code': p.returncode} for k, p in self.processes.items()}
            self.report['seconds'] = time.monotonic() - started
            self.save('report.json', self.report)
            print(self.report['result'], self.root, flush=True)
        return 0 if self.report['result'] == 'PASS' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--godot', type=Path, default=Path('C:/Godot/godot/bin/godot.windows.editor.double.x86_64.exe'))
    parser.add_argument('--output', type=Path, default=Path('C:/distributed-world-simulator/artifacts/shared-gameplay-20261031'))
    parser.add_argument('--expected-head')
    parser.add_argument('--restart-after-seconds', type=int, default=110)
    args = parser.parse_args()
    require(args.restart_after_seconds >= 60, 'RESTART_WINDOW_TOO_SHORT')
    return SharedGameplayCheck(args).run()


if __name__ == '__main__':
    raise SystemExit(main())
