#!/usr/bin/env python3
"""Run the bounded MVP3 seam adapter. PASS_SUBGATE_ONLY is not MVP3 acceptance."""
from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parent
SM1 = 'res://scripts/runtime/networked_gameplay/sm1/'
SCENE = 'res://scenes/labs/mvp/v0_mvp_seam_shared_scene.tscn'
DRIVER = 'res://tests/fixtures/v0_mvp/seam_input_driver.gd'
ENGINE_SHA = {
    'linux': 'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7',
    'win32': '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5',
}
ERRORS = re.compile(r'(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error')
IDENTITY = {
    'product_session_id': 'session/sm1/graphical-acceptance',
    'logical_player_id': 'player/sm1-graphical-a',
    'player_entity_id': 'entity/sm1-graphical-a',
    'spawn_generation': 1,
}


def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    os.replace(temporary, path)


def normalize(value: object) -> object:
    # Mirrors NetworkContractUtils.canonicalize. This corridor uses exact quarter-metre floats.
    if isinstance(value, float):
        require(math.isfinite(value), 'NONFINITE_CANONICAL_STATE')
        return int(value) if value.is_integer() else value
    if isinstance(value, dict):
        return {k: normalize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [normalize(v) for v in value]
    return value


def state_hash(value: dict) -> str:
    encoded = json.dumps(normalize(value), sort_keys=True, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
    return hashlib.sha256(encoded.encode('utf-8')).hexdigest()


def subgate_errors(reports: dict, head: str, run_id: str) -> list[str]:
    errors: list[str] = []
    def check(ok: bool, code: str) -> None:
        if not ok:
            errors.append(code)
    try:
        names = ['authority-a', 'authority-b', 'gateway', 'client-a', 'client-b']
        check(set(reports) == set(names), 'EXACT_FIVE_PROCESSES')
        if set(reports) != set(names):
            return errors
        check(all(r.get('passed') is True and r.get('state') == 'COMPLETE' for r in reports.values()), 'PROCESS_FAILURE')
        pids = [reports[n].get('process_id') for n in names]
        check(all(isinstance(p, int) and not isinstance(p, bool) and p > 0 for p in pids) and len(set(pids)) == 5, 'PROCESS_ISOLATION')
        a, b, gateway = reports['client-a'], reports['client-b'], reports['gateway']
        for client_id, client in [('a', a), ('b', b)]:
            prefix = client_id + ':'
            check(client.get('subject_head') == head and client.get('run_id') == run_id, prefix + 'EXACT_SUBJECT')
            check(client.get('schema') == 'distributed_world_simulator.mvp3_seam_client_subgate.v1' and client.get('scene_path') == SCENE and client.get('client_id') == client_id, prefix + 'SCENE_IDENTITY')
            check(client.get('canonical_state_owned') is False and client.get('two_independent_players_integrated') is False and client.get('mvp3_predicate_verified') is False, prefix + 'SCOPE_OR_OWNERSHIP_OVERCLAIM')
            check(not client.get('error') and client.get('body_visible') is True, prefix + 'PRESENTATION_ERROR')
            check(str(client.get('display_server', '')).lower() not in ['', 'headless', 'dummy'], prefix + 'GRAPHICAL_DISPLAY')
            check(client.get('screenshot_saved') is True, prefix + 'SCREENSHOT_REQUIRED')
            check(client.get('connect_attempts') == 1, prefix + 'ONE_CONNECT_ATTEMPT')
            for field in ['body', 'camera']:
                check(isinstance(client.get(field + '_instance_first'), int) and client[field + '_instance_first'] > 0 and client.get(field + '_instance_last') == client[field + '_instance_first'], prefix + field.upper() + '_INSTANCE_CHANGED')
            continuity = client['continuity']
            check(continuity.get('error') == '' and continuity.get('canonical_state_owned') is False and continuity.get('goal_reached') is True, prefix + 'CONTINUITY_FAILURE')
            events = continuity.get('transport_events', [])
            check(len(events) == 1 and events[0].get('event_type') == 'PEER_CONNECTED' and isinstance(events[0].get('observed_ms'), (int, float)), prefix + 'OBSERVED_CONNECTION_REQUIRED')
            check(continuity.get('connect_count') == 1 and continuity.get('reconnect_count') == 0 and continuity.get('disconnect_count') == 0, prefix + 'CONNECTION_CONTINUITY')
            samples = continuity['samples']
            check(80 <= len(samples) <= 256, prefix + 'BOUNDED_SAMPLE_COUNT')
            route, epochs, movement = [], [], {}
            previous = None
            for sample in samples:
                state = sample['state']
                epoch, owner = sample['authority_epoch'], sample['authority_id']
                check(all(state.get(k) == v for k, v in IDENTITY.items()), prefix + 'STABLE_IDENTITY')
                check(sample['state_checksum'] == state_hash(state), prefix + 'CHECKSUM')
                x = state['position_x']
                check(isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x), prefix + 'FINITE_POSITION')
                if not route or owner != route[-1]:
                    route.append(owner)
                    epochs.append(epoch)
                    if previous:
                        check(epoch == previous['authority_epoch'] + 1, prefix + 'MONOTONIC_ROUTE_EPOCH')
                        check((owner == 'authority/b' and x >= 10.0) or (owner == 'authority/a' and x <= 0.0), prefix + 'REAL_SEAM_COORDINATE')
                if previous:
                    old = previous['state']
                    step = abs(x - old['position_x'])
                    check(step <= 0.250001, prefix + 'NO_TELEPORT')
                    check(state['world_revision'] > old['world_revision'] and state['last_input_sequence'] > old['last_input_sequence'], prefix + 'MONOTONIC_COMMAND_STATE')
                    if owner == previous['authority_id']:
                        check(epoch == previous['authority_epoch'], prefix + 'NO_SILENT_EPOCH_CHANGE')
                        if step > 0.000001:
                            movement[str(epoch)] = movement.get(str(epoch), 0) + 1
                else:
                    check(x == 0 and owner == 'authority/a' and epoch == 1, prefix + 'INITIAL_STATE')
                previous = sample
            check(route == ['authority/a', 'authority/b', 'authority/a'] and epochs == [1, 2, 3], prefix + 'EXACT_ROUTE')
            check(continuity.get('route_history') == route and continuity.get('epochs') == epochs, prefix + 'RECOMPUTED_ROUTE')
            check(movement == continuity.get('movement_steps_by_epoch') and all(movement.get(str(e), 0) >= 2 for e in [1, 2, 3]), prefix + 'POST_SEAM_CONTROL')
            check(continuity.get('last_state') == samples[-1]['state'] and continuity.get('state_checksum') == samples[-1]['state_checksum'], prefix + 'FINAL_STATE')
            surface = client['surface']
            check(surface.get('configured') is True and surface.get('mesh_count', 0) > 0 and surface.get('canonical_state_owned') is False and surface.get('mutable_matter_store_retained') is False, prefix + 'IMMUTABLE_SURFACE')
            receipts = client.get('command_receipts', [])
            check(client.get('command_results') == len(receipts), prefix + 'COMMAND_RECEIPT_COUNT')
            if client_id == 'a':
                check(len(receipts) == len(samples), prefix + 'ACK_FOR_EVERY_INPUT')
                for receipt, sample in zip(receipts, samples):
                    check(receipt['sequence'] == sample['state']['last_input_sequence'] and receipt['revision'] == sample['state']['world_revision'] and receipt['authority_epoch'] == sample['authority_epoch'] and receipt['request_id'] == f"mvp3/{run_id}/{receipt['sequence']}", prefix + 'ACK_CORRELATION')
            else:
                check(receipts == [], prefix + 'OBSERVER_MUST_NOT_CLAIM_INPUT_AUTHORITY')
        check(a['continuity']['samples'] == b['continuity']['samples'], 'BOTH_CLIENTS_OBSERVE_IDENTICAL_HISTORY')
        check(a['surface']['bootstrap_hash'] == b['surface']['bootstrap_hash'] and a['surface']['descriptor'] == b['surface']['descriptor'], 'SHARED_SURFACE')
        check(a['user_data_dir'] != b['user_data_dir'] and all(c.get('user_data_dir') for c in [a, b]), 'USER_DATA_ISOLATION')
        check(a['transport_session_id'] != b['transport_session_id'] and all(c.get('transport_session_id') for c in [a, b]), 'TRANSPORT_SESSION_ISOLATION')
        check(gateway.get('handoff_count') == 2 and gateway.get('authority_epoch') == 3 and gateway.get('active_authority_id') == 'authority/a', 'REAL_GATEWAY_ROUTE')
        check(gateway.get('canonical_gameplay_owner') is False and gateway.get('client_connection_count') == 2, 'GATEWAY_NOT_NEW_OWNER')
        check(gateway.get('last_state_checksum') == a['continuity']['state_checksum'] and gateway.get('last_world_revision') == a['continuity']['last_state']['world_revision'], 'GATEWAY_FINAL_CONVERGENCE')
        check(gateway.get('counters', {}).get('client_disconnects') == 0 and gateway.get('counters', {}).get('client_reconnects') == 0, 'GATEWAY_OBSERVED_CONTINUITY')
        check(gateway.get('transfer_payload_retained') is False and gateway.get('authority_runtime_recovery_pending') is False and gateway.get('authority_recovery_blocks_writes') is False, 'NO_PENDING_HANDOFF')
        for name, expected_epoch, active in [('authority-a', 3, True), ('authority-b', 2, False)]:
            authority = reports[name]
            check(authority.get('authority_epoch') == expected_epoch and authority.get('active') is active and authority.get('private_persistence_owner') is False, name + ':ROLE')
            check(authority['state_checksum'] == state_hash(authority['shared_state']), name + ':CHECKSUM')
            for counter in ['freezes', 'warm_loads', 'retires', 'activations']:
                check(authority.get('counters', {}).get(counter) == 1, name + ':' + counter)
        check(reports['authority-a']['shared_state'] == a['continuity']['last_state'], 'ACTIVE_AUTHORITY_FINAL_STATE')
    except (KeyError, TypeError, ValueError, IndexError, RuntimeError, OverflowError) as exc:
        errors.append('MALFORMED_EVIDENCE:' + type(exc).__name__)
    return sorted(set(errors))


def negative_controls(reports: dict, head: str, run_id: str) -> list[str]:
    cases = []
    def case(name, mutation):
        altered = copy.deepcopy(reports)
        mutation(altered)
        require(bool(subgate_errors(altered, head, run_id)), 'NEGATIVE_CONTROL_ACCEPTED:' + name)
        cases.append(name)
    case('missing_second_client', lambda r: r.pop('client-b'))
    case('wrong_head', lambda r: r['client-a'].__setitem__('subject_head', '0' * 40))
    case('respawned_body', lambda r: r['client-a'].__setitem__('body_instance_last', 0))
    case('recreated_camera', lambda r: r['client-a'].__setitem__('camera_instance_last', 0))
    case('fabricated_connect_count', lambda r: r['client-a']['continuity'].__setitem__('transport_events', []))
    case('observed_reconnect_hidden', lambda r: r['client-a']['continuity']['transport_events'].append({'event_type': 'PEER_CONNECTED', 'observed_ms': 9999}))
    case('scope_overclaim', lambda r: r['client-a'].__setitem__('mvp3_predicate_verified', True))
    case('changed_entity', lambda r: r['client-a']['continuity']['samples'][-1]['state'].__setitem__('player_entity_id', 'other'))
    case('no_post_return_control', lambda r: r['client-a']['continuity']['movement_steps_by_epoch'].__setitem__('3', 0))
    case('synthetic_gateway_handoff', lambda r: r['gateway'].__setitem__('handoff_count', 0))
    case('wrong_active_owner', lambda r: r['authority-a'].__setitem__('active', False))
    case('shared_process', lambda r: r['client-b'].__setitem__('process_id', r['client-a']['process_id']))
    case('second_client_not_rendered', lambda r: r['client-b'].__setitem__('body_visible', False))
    case('observer_forged_as_second_player', lambda r: r['client-b'].__setitem__('command_results', 1))
    return cases


def free_ports() -> list[int]:
    sockets = []
    try:
        for _ in range(3):
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.bind(('127.0.0.1', 0))
            sockets.append(sock)
        return [sock.getsockname()[1] for sock in sockets]
    finally:
        for sock in sockets:
            sock.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', default=os.environ.get('GODOT_BIN', ''))
    parser.add_argument('--automated', action='store_true')
    args = parser.parse_args()
    engine = Path(args.engine).expanduser().resolve()
    require(engine.is_file(), 'Set GODOT_BIN or --engine to the approved double-precision Godot binary')
    require(sys.platform in ENGINE_SHA and sha(engine) == ENGINE_SHA[sys.platform], 'UNAPPROVED_ENGINE')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    require(re.fullmatch('[0-9a-f]{40}', head) is not None, 'EXACT_HEAD_REQUIRED')
    require(not subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT, text=True).strip(), 'TRACKED_CHECKOUT_DIRTY')
    require(not os.environ.get('EXPECTED_HEAD') or os.environ['EXPECTED_HEAD'] == head, 'WRONG_CHECKOUT')
    run_id = uuid.uuid4().hex
    out = ROOT / 'artifacts' / 'mvp3-exact' / run_id
    out.mkdir(parents=True, exist_ok=False)
    summary = {'schema': 'distributed_world_simulator.mvp3_seam_subgate.v1', 'subject_head': head, 'run_id': run_id, 'automated_input': args.automated, 'started_at_utc': datetime.now(timezone.utc).isoformat(), 'status': 'RUNNING', 'mvp3_predicate_verified': False, 'two_independent_players_integrated': False, 'whole_mvp_acceptance': False, 'runtime_merge': False, 'main_merge': False, 'independent_context': False}
    write(out / 'result.json', summary)
    processes: dict[str, subprocess.Popen] = {}
    streams = []
    timeout = 180 if args.automated else 86400
    def run_check(name: str, command: list[str], limit: int) -> None:
        log = out / (name + '.log')
        with log.open('w', encoding='utf-8') as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=limit, check=False)
        text = log.read_text(encoding='utf-8', errors='replace')
        require(result.returncode == 0 and not ERRORS.search(text), name + ':FAILED')
    def spawn(name: str, entry: list[str], options: list[str], graphical: bool = False) -> None:
        profile = out / 'user-data' / name
        for child in ['data', 'config', 'cache']:
            (profile / child).mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, HOME=str(profile), USERPROFILE=str(profile), APPDATA=str(profile / 'data'), LOCALAPPDATA=str(profile / 'data'), XDG_DATA_HOME=str(profile / 'data'), XDG_CONFIG_HOME=str(profile / 'config'), XDG_CACHE_HOME=str(profile / 'cache'), BREAKPOINT_RUNTIME_DISABLED='1', GODOT_SILENCE_ROOT_WARNING='1')
        render = ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', '960x640'] if graphical else ['--headless']
        command = [str(engine), '--path', str(ROOT), '--log-file', str(out / (name + '.engine.log'))] + render + entry + ['--'] + options + [f'--result-file={out / (name + ".json")}', f'--timeout-ms={timeout * 1000}']
        stream = (out / (name + '.console.log')).open('w', encoding='utf-8')
        streams.append(stream)
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
        processes[name] = process
        write(out / (name + '.launch.json'), {'process_id': process.pid, 'subject_head': head, 'engine_sha256': sha(engine), 'arguments': command, 'profile': str(profile)})
    def wait_ready(name: str) -> None:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            path = out / (name + '.json')
            if path.is_file():
                value = json.loads(path.read_text(encoding='utf-8'))
                if value.get('state') == 'LISTENING':
                    return
                require(value.get('state') != 'FAILED', name + ':STARTUP_FAILED')
            require(processes[name].poll() is None, name + ':EXITED_BEFORE_READY')
            time.sleep(0.05)
        raise RuntimeError(name + ':READY_TIMEOUT')
    try:
        run_check('import', [str(engine), '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'], 120)
        run_check('continuity-contract', [str(engine), '--headless', '--path', str(ROOT), '--script', 'res://tests/runtime/test_v0_mvp_seam_continuity.gd'], 60)
        gateway_port, a_port, b_port = free_ports()
        spawn('authority-a', ['--script', SM1 + 'sm1_6_authority_worker.gd'], [f'--port={a_port}', '--host=127.0.0.1', '--authority-id=authority/a', '--initial-active=true', '--initial-epoch=1'])
        spawn('authority-b', ['--script', SM1 + 'sm1_6_authority_worker.gd'], [f'--port={b_port}', '--host=127.0.0.1', '--authority-id=authority/b', '--initial-active=false', '--initial-epoch=1'])
        wait_ready('authority-a')
        wait_ready('authority-b')
        spawn('gateway', ['--script', SM1 + 'sm1_6_gateway_worker.gd'], [f'--client-port={gateway_port}', '--client-host=127.0.0.1', f'--authority-a-port={a_port}', '--authority-a-host=127.0.0.1', f'--authority-b-port={b_port}', '--authority-b-host=127.0.0.1'])
        wait_ready('gateway')
        for client_id in ['a', 'b']:
            entry = ['--script', DRIVER] if args.automated else [SCENE]
            spawn('client-' + client_id, entry, [f'--port={gateway_port}', '--host=127.0.0.1', f'--client-id={client_id}', f'--subject-head={head}', f'--run-id={run_id}'], True)
        print('MVP3 scene: A/D or arrows in operator A; cross x=10, return below x=0, then Esc. B is an observer.', flush=True)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            codes = {name: process.poll() for name, process in processes.items()}
            require(all(code in [None, 0] for code in codes.values()), 'PROCESS_FAILED:' + str(codes))
            if all(code is not None for code in codes.values()):
                break
            time.sleep(0.05)
        require(all(process.poll() == 0 for process in processes.values()), 'PROCESS_COMPLETION_TIMEOUT')
        for stream in streams:
            stream.flush()
        reports = {name: json.loads((out / (name + '.json')).read_text(encoding='utf-8')) for name in processes}
        errors = subgate_errors(reports, head, run_id)
        for name, process in processes.items():
            require(reports[name]['process_id'] == process.pid, 'PID_REPORT_MISMATCH:' + name)
        for path in out.glob('*.log'):
            require(not ERRORS.search(path.read_text(encoding='utf-8', errors='replace')), 'GODOT_ERROR:' + path.name)
        for client in ['client-a', 'client-b']:
            image = out / (client + '.json.png')
            require(image.is_file() and image.stat().st_size > 1000 and image.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), 'SCREENSHOT_MISSING:' + client)
        require(not errors, 'EVIDENCE_REJECTED:' + ';'.join(errors))
        summary['negative_controls'] = negative_controls(reports, head, run_id)
        summary['status'] = 'PASS_SUBGATE_ONLY'
        summary['integration_gap'] = 'The accepted SM1 process owner has one controllable actor plus an observer. MVP2 two independently controlled M3 actors have not yet been bound to this authority transition. Do not mark MVP3 VERIFIED.'
    except Exception as exc:
        summary['status'] = 'FAIL'
        summary['error'] = type(exc).__name__ + ': ' + str(exc)
    finally:
        for process in processes.values():
            if process.poll() is None:
                process.terminate()
        for process in processes.values():
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        for stream in streams:
            stream.close()
        summary['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        summary['process_exit_codes'] = {name: process.returncode for name, process in processes.items()}
        write(out / 'result.json', summary)
        members = []
        for path in sorted(out.rglob('*')):
            relative = path.relative_to(out)
            if path.is_file() and 'user-data' not in relative.parts and path.name != 'manifest.json':
                members.append({'path': relative.as_posix(), 'size': path.stat().st_size, 'sha256': sha(path)})
        write(out / 'manifest.json', {'schema': 'distributed_world_simulator.mvp3_artifact_manifest.v1', 'subject_head': head, 'run_id': run_id, 'members': members, 'contains_source_export': False})
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print('MVP3_ARTIFACTS=' + str(out))
    return 0 if summary['status'] == 'PASS_SUBGATE_ONLY' else 1


if __name__ == '__main__':
    sys.exit(main())
