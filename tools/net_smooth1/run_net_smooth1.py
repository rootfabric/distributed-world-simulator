#!/usr/bin/env python3
"""Exact-source tests and real Earth server/two-client playtest; no desktop input."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import secrets
import threading
import shutil
import socket
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/live2'))
from live2_automation_client import request
from analyze_net_smooth1 import write_report
from owned_process_cleanup import finalize_owned_processes, preflight_no_smooth_godot

TESTS = [
 'tests/runtime/test_net_smooth1_r3c4_periodic_frame_headroom.gd',
 'tests/runtime/test_net_smooth1_r42_r3c2_phased_item_publication.gd',
 'tests/characters/test_net_smooth1_r42_r3c2_avatar_prewarm.gd',
 'tests/runtime/test_net_smooth1_r42_r3c_async_leave.gd',
 'tests/runtime/test_net_smooth1_r42_r3c_queued_join.gd',
 'tests/runtime/test_net_smooth1_r42_r3_committed_view.gd',
 'tests/runtime/test_net_smooth1_r42_r3_writer_nested_alias.gd',
 'tests/runtime/test_net_smooth1_r42_r3_slow_item_movement.gd',
 'tests/runtime/test_net_smooth1_r42_p1b_item_async_canary.gd',
 'tests/runtime/test_net_smooth1_r42_seam_full_snapshot_wire_checksum.gd',
 'tests/runtime/test_net_smooth1_r42_p1b_periodic_completion_order.gd',
 'tests/runtime/test_net_smooth1_r42_p1_async_durable_proof.gd',
 'tests/runtime/test_net_smooth1_r42_revision_fence_diagnostics.gd',
 'tests/network/test_net_smooth1_r31_compact_wire_checksum.gd',
 'tests/runtime/test_net_smooth1_r41_p1_fifo_disconnect_repair.gd',
 'tests/runtime/test_net_smooth1_r41_pending_durable_gate.gd',
 'tests/network/test_net_smooth1_seam_change_delivery.gd',
 'tests/runtime/test_net_smooth1_remote_owner_reconnect.gd',
 'tests/network/test_net_smooth1_snapshot_hotpath.gd',
 'tests/network/test_net_smooth1_hold_continuity.gd',
 'tests/network/test_net_smooth1_gap_semantics.gd',
 'tests/runtime/test_net_smooth1_async_checkpoint.gd',
 'tests/network/test_nx2_realtime_traffic_separation.gd',
 'tests/network/test_nx3_fixed_tick_authoritative_simulation.gd',
 'tests/network/test_nx4_client_prediction_reconciliation.gd',
 'tests/network/test_nx5_remote_snapshot_interpolation.gd',
 'tests/network/test_nx5_remote_snapshot_interpolation_integration.gd',
 'tests/runtime/test_m6_dedicated_recovery_contracts.gd',
 'tests/runtime/test_v0_p3_m6_resource_replay_outbox.gd',
 'tests/runtime/test_v0_user1_product_seam_bridge.gd',
 'tests/characters/test_char2_network_avatar_client_presentation.gd',
 'tests/characters/test_char2_product_camera_toggle.gd',
]
PROCESS_TESTS = [
 'tests/runtime/test_m6_dedicated_recovery_processes.gd',
 'tests/runtime/test_m7_playable_networked_processes.gd',
 'tests/runtime/test_m7_playable_networked_recovery_processes.gd',
 'tests/network/test_nx2_physical_channel_processes.gd',
]
BAD_LOG = ('SCRIPT ERROR:', 'Parse Error:', 'Compile Error:', 'ERROR:')


def dump(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding='utf-8')


def git(*args: str) -> str:
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()


def identity(godot: Path) -> dict:
    asset_root=ROOT/'assets/external/quaternius'
    asset_hashes={}
    if asset_root.is_dir():
        for path in sorted(asset_root.rglob('*')):
            if path.is_file() and path.suffix not in ('.import','.uid'):
                asset_hashes[str(path.relative_to(asset_root)).replace('\\','/')]=hashlib.sha256(path.read_bytes()).hexdigest()
    cpu_quota=Path('/sys/fs/cgroup/cpu.max')
    return {'asset_count':len(asset_hashes),
            'asset_manifest_sha256':hashlib.sha256(json.dumps(asset_hashes,sort_keys=True).encode()).hexdigest(),
            'cpu_quota':cpu_quota.read_text().strip() if cpu_quota.is_file() else None,'head':git('rev-parse','HEAD'), 'tree':git('rev-parse','HEAD^{tree}'),
            'tracked_dirty':bool(git('diff','HEAD','--name-only')),
            'godot_version':subprocess.check_output([str(godot),'--version'],text=True).strip(),
            'godot_sha256':hashlib.sha256(godot.read_bytes()).hexdigest(),
            'platform':platform.platform(),'python':sys.version,'cpu_count':os.cpu_count(),
            'session_name':os.environ.get('SESSIONNAME',''),'display':os.environ.get('DISPLAY','')}


def environment(root: Path) -> dict[str,str]:
    env = dict(os.environ)
    # Never inherit tracing/fault injection from another test process.
    for key in list(env):
        if key.startswith('DWS_NET_SMOOTH_'): del env[key]
    for key,folder in [('HOME','home'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),
                       ('XDG_CACHE_HOME','cache'),('APPDATA','data'),('LOCALAPPDATA','data')]:
        path=root/'userdata'/folder;path.mkdir(parents=True,exist_ok=True);env[key]=str(path)
    env.update(BREAKPOINT_RUNTIME_DISABLED='1',GODOT_SILENCE_ROOT_WARNING='1')
    return env


def run_script(godot: Path, script: str, root: Path, timeout: float) -> dict:
    name=Path(script).stem;log=root/(name+'.log')
    command=[str(godot),'--headless','--path',str(ROOT),'--script','res://'+script]
    with log.open('w',encoding='utf-8') as stream:
        try:
            result=subprocess.run(command,cwd=ROOT,env=environment(root/name),stdout=stream,
                                  stderr=subprocess.STDOUT,timeout=timeout)
            code=result.returncode
        except subprocess.TimeoutExpired:
            code=124
    text=log.read_text(encoding='utf-8',errors='replace')
    return {'test':script,'exit_code':code,'passed':code==0 and not any(x in text for x in BAD_LOG),
            'log':str(log),'sha256':hashlib.sha256(log.read_bytes()).hexdigest()}


def import_project(godot: Path, root: Path, timeout: float) -> None:
    log=root/'cold-import.log'
    with log.open('w',encoding='utf-8') as stream:
        result=subprocess.run([str(godot),'--headless','--editor','--path',str(ROOT),'--import'],
             cwd=ROOT,env=environment(root/'import'),stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
    if result.returncode or any(x in log.read_text(errors='replace') for x in BAD_LOG):
        raise RuntimeError(f'cold import failed: {log}')


def free_port(udp: bool = False) -> int:
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM if udp else socket.SOCK_STREAM) as s:
        s.bind(('127.0.0.1',0));return s.getsockname()[1]


def bridge(port: int, token: str, method: str, params: dict | None = None,
           timeout: float = 5.0) -> dict:
    reply=request(port,token,method,params or {},timeout=timeout)
    if not reply.get('ok'): raise RuntimeError(f'{method}: {reply}')
    return reply['result']


def play(args, manifest: dict) -> None:
    root=args.output
    udp=free_port(True); ports={name:free_port() for name in ('a','b')}
    while ports['a']==ports['b']: ports['b']=free_port()
    token=secrets.token_urlsafe(24)
    manifest.update(udp_port=udp,automation_ports=ports,process_exit_codes={},errors=[],completed=False,
                    snapshot_stages_required=True,
                    durable_stages_required=args.scenario in ('durable-commands', 'r3-slow-item'),
                    renderer='opengl3' if args.mode=='gui' else 'headless',resolution='900x600',max_fps=60,
                    vsync='disabled',phase_results=[],checkpoint_mode=args.checkpoint_mode,
                    r3c_async_admission=args.r3c_async_admission,
                    slow_item_writer_ms=args.slow_item_writer_ms,
                    r3c2_avatar_prewarm=args.r3c2_avatar_prewarm,
                    r3c2_server_phased=args.r3c2_server_phased,
                    r3c3_staged_earth=args.r3c3_staged_earth,
                    r3c21_frame_paced_presentation=args.r3c21_frame_paced_presentation,
                    r3c4_periodic_frame_pacing=args.r3c4_periodic_frame_pacing,
                    r3c4r2_worker_envelope=args.r3c4r2_worker_envelope,
                    r3c4r30_stage_attribution=args.r3c4r30_stage_attribution,
                    r3c4r31_replay_projection=args.r3c4r31_replay_projection,
                    r3c4r31b_durable_attribution=args.r3c4r31b_durable_attribution,
                    r31bp1_durable_chunks=args.r31bp1_durable_chunks,
                    r31bp20_validator_attribution=args.r31bp20_validator_attribution,
                    r31p22_loop_attribution=args.r31p22_loop_attribution,
                    scenario=args.scenario)
    processes: dict[str,subprocess.Popen] = {}; streams=[]
    def spawn(role: str) -> None:
        target=root/role;target.mkdir(parents=True)
        env=environment(target)
        env.update(DWS_NET_SMOOTH_TRACE_DIR=str(target),DWS_NET_SMOOTH_RUN_ID=manifest['run_id'],
                   DWS_NET_SMOOTH_ROLE=role)
        if role == args.inject_stall_role:
            env['DWS_NET_SMOOTH_INJECT_STALL_MS']=str(args.inject_stall_ms)
        if role == 'server' and args.checkpoint_mode=='sync':
            env['DWS_NET_SMOOTH_SYNC_CHECKPOINTS']='1'
        if role == 'server' and args.r3c_async_admission:
            # The canary flag is passed only to the authoritative server.
            env['DWS_NET_R3C_ASYNC_ADMISSION']='1'
        if role in ('a', 'b') and args.r3c2_avatar_prewarm:
            # Visual-only: only clients prewarm reusable Quaternius rigs during
            # Earth scene loading, never at JOIN_ACK or while applying ITEM.
            env['DWS_NET_R3C2_AVATAR_PREWARM']='1'
        if role in ('a','b') and args.r3c3_staged_earth:
            env['DWS_NET_R3C3_STAGED_EARTH']='1'
        if role in ('a','b') and args.r3c21_frame_paced_presentation:
            env['DWS_NET_R3C21_FRAME_PACED_PRESENTATION']='1'
        if role == 'server' and args.r3c2_server_phased:
            env['DWS_NET_R3C2_PHASED_ITEM_PUBLICATION']='1'
        if role == 'server' and args.r3c4_periodic_frame_pacing:
            # R3C.4 frame pacing is a server-only authority concern.
            env['DWS_NET_R3C4_PERIODIC_FRAME_PACING']='1'
        if role == 'server' and args.r3c4r2_worker_envelope:
            # Immutable periodic M6 envelope only; never mutate client env.
            env['DWS_NET_R3C4_R2_WORKER_ENVELOPE']='1'

        if role == 'server' and args.r3c4r30_stage_attribution:
            # Diagnostics only; never route to clients or alter M6 semantics.
            env['DWS_NET_R3C4_R30_STAGE_ATTRIBUTION']='1'
        if role == 'server' and args.r3c4r31_replay_projection:
            env['DWS_NET_R3C4_R31_REPLAY_PROJECTION']='1'
        if role == 'server' and args.r3c4r31b_durable_attribution:
            env['DWS_NET_R3C4_R31B_DURABLE_ATTRIBUTION']='1'
        if role == 'server' and args.r31bp1_durable_chunks:
            # R31b P1 chunk cache is a server-only authority concern.
            env['DWS_NET_R31BP1_DURABLE_CHUNKS']='1'
        if role == 'server' and args.r31bp20_validator_attribution:
            # P2.0 source profiling only; never reaches client or M6 writer.
            env['DWS_NET_R31BP20_VALIDATOR_ATTRIBUTION']='1'
        if role == 'server' and args.r31p22_loop_attribution:
            # P2.2 server-only frame/process/compact-wire timing probe.
            env['DWS_NET_R31P22_LOOP_ATTRIBUTION']='1'
        if role == 'server' and args.slow_item_writer_ms > 0:
            # Test-only worker injection, never delay the main-thread loop.
            env['DWS_NET_SMOOTH_TEST_HOOKS']='1'
            env['DWS_NET_SMOOTH_TEST_ITEM_DELAY_MS']=str(args.slow_item_writer_ms)
        engine=[str(args.godot),'--path',str(ROOT),'--max-fps','60','--disable-vsync']
        if role=='server' or args.mode=='headless': engine += ['--headless']
        else: engine += ['--rendering-driver','opengl3','--windowed','--resolution','900x600',
                         '--position','20,60' if role=='a' else '940,60']
        game=['--',f'--role={"dedicated-server" if role=="server" else "game-client"}',
              '--network-mvp','--world=earth','--server-address=127.0.0.1',f'--server-port={udp}',
              '--network-debug','--network-debug-stay-open',f'--network-profile={args.profile}',
              f'--node-id=smooth-{role}-{manifest["run_id"]}',f'--instance-id={manifest["run_id"]}',
              f'--shutdown-after-ms={int((args.startup_timeout*3+args.warmup+args.duration+120)*1000)}']
        if role=='server':
            game += ['--product-seam',f'--persistence-root={root/"world"}']
        else:
            game += [f'--player-identity={role}','--automation-control',
                     f'--automation-control-token={token}',f'--automation-control-port={ports[role]}',
                     f'--automation-control-output-dir={target/"captures"}']
        stream=(target/'runtime.log').open('w',encoding='utf-8');streams.append(stream)
        processes[role]=subprocess.Popen(engine+game,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT)
        manifest.setdefault('pids',{})[role]=processes[role].pid
        manifest.setdefault('commands',{})[role]=[a if not a.startswith('--automation-control-token=')
                                                  else '--automation-control-token=<redacted>' for a in engine+game]
        dump(root/'manifest.json',manifest)
    def alive() -> None:
        for role,p in processes.items():
            if p.poll() is not None: raise RuntimeError(f'{role} exited early: {p.returncode}')
    def wait_ready(role: str) -> None:
        deadline=time.monotonic()+args.startup_timeout;last=''
        while time.monotonic()<deadline:
            alive(); state = None
            try:
                if role=='server':
                    text=(root/role/'runtime.log').read_text(encoding='utf-8',errors='replace')
                    if '"event":"node_ready"' in text or '"event": "node_ready"' in text:
                        return
                else:
                    state=bridge(ports[role],token,'state.get',{'kind':'automation'})['automation']
                    if state.get('connection_state')=='CONNECTED': return
            except (OSError,RuntimeError,KeyError,ValueError) as exc: last=str(exc)
            if state and state.get('connection_state') in ('FAILED','REJECTED'):
                raise RuntimeError(f'{role}: permanent connection failure: {state}')
            time.sleep(.25)
        raise RuntimeError(f'{role} readiness timeout; {last}')
    def command(role: str, line: str) -> dict:
        return bridge(ports[role],token,'command.execute',{'line':line})['result']
    try:
        if args.mode == 'gui' and os.name == 'nt':
            # Do not kill Godot editors or another agent's runs. Refuse to
            # start if another net-smooth Godot from this binary directory
            # is alive: previous failure must not pollute this paired arm.
            preflight_no_smooth_godot(args.godot)
            manifest['preflight_no_other_smooth_godot'] = True
        spawn('server');wait_ready('server')
        for role in ('a','b'): spawn(role)
        for role in ('a','b'): wait_ready(role)
        # Both clients use the real Earth game and ordinary network movement path.
        time.sleep(args.warmup);alive()
        for role in ('a','b'):
            # Avatar presentation can lag world generation under parallel load;
            # poll within a bounded budget instead of a single post-warmup check.
            deadline=time.monotonic()+30.0;status=None;details={}
            while True:
                alive()
                try:
                    status=command(role,'character.remote.status')
                except (OSError, RuntimeError, ValueError, KeyError):
                    status=None
                if status is not None:
                    details=status.get('details',{})
                    dump(root/role/'avatar-status.json',status)
                    if details.get('remote_count')==1:
                        break
                if time.monotonic()>deadline:
                    break
                time.sleep(.5)
            dump(root/role/'avatar-status.json',status)
            if details.get('remote_count') != 1: raise RuntimeError(f'{role}: remote avatar missing')
            if args.mode=='gui':
                remote=list(details.get('remote_players',{}).values())
                if len(remote)!=1 or remote[0].get('provider_id')!='avatar/quaternius' or \
                   remote[0].get('asset_mode')!='QUATERNIUS_RETARGET' or not remote[0].get('ready') or remote[0].get('legacy_capsule_visible',True):
                    raise RuntimeError(f'{role}: actual Quaternius required for GUI acceptance')
            for _ in range(2):
                command(role,'character.camera.toggle')
            dump(root/role/'initial-state.json',bridge(ports[role],token,'state.get',{'kind':'automation'}))
        # The normative measurement window must contain only the continuous
        # connected movement phase. Scenario reconnect stages are functional
        # acceptance and are deliberately measured separately: the probe
        # closes the window (measure.end) before any planned reconnect and,
        # for r31, opens it only after the roundtrip stages have finished.
        measure_closed = False
        def close_measure_window() -> None:
            # Each probe must ACK the local measure.end fence before any
            # planned reconnect, final screenshot, checkpoint or teardown.
            # Waiting an arbitrary 0.5/1.2s under high host load is not
            # enough; missing ACK is INCONCLUSIVE, never frame PASS.
            nonlocal measure_closed
            if measure_closed:
                return
            for role in processes:
                (root/role/'measure.end').touch()
            measure_closed = True
            pending=set(processes)
            deadline=time.monotonic()+max(5.0,min(45.0,args.startup_timeout/4))
            while pending and time.monotonic()<deadline:
                alive()
                for role in tuple(pending):
                    ack=root/role/'measure.end.ack'
                    if not ack.is_file():
                        continue
                    value=ack.read_text(encoding='utf-8').strip()
                    if not value.isdigit() or int(value)<=0:
                        raise RuntimeError(f'{role}: INVALID_MEASURE_END_ACK')
                    pending.remove(role)
                if pending:
                    time.sleep(.05)
            if pending:
                raise RuntimeError('NET_SMOOTH_MEASURE_END_ACK_TIMEOUT:'+
                                   ','.join(sorted(pending)))
            manifest['measurement_closed_roles']=sorted(processes)
            manifest['measurement_close_ack_complete']=True
        if args.scenario != 'r31-reconnect-roundtrip':
            for role in processes: (root/role/'measure.start').touch()
        started=time.monotonic()
        def automation(role: str) -> dict:
            return bridge(ports[role], token, 'state.get', {'kind': 'automation'})['automation']
        def drive(role: str, x: float, z: float, yaw: float = 0.0, sprint: bool = False) -> None:
            bridge(ports[role], token, 'movement.set', {'move_x': x, 'move_z': z,
                'look_yaw': yaw, 'sprint': sprint, 'ttl_ms': 900})
        def durable_phase() -> dict:
            # R4.0 durable-workload diagnostics: >=20 real authoritative durable
            # commands of >=2 allowlisted types through the ordinary M4 client
            # seam, plus one duplicate operation_id replay check. A successful
            # blocking result is only returned after the server-side
            # durable-before-ACK commit, and rejections never count as commits.
            results=[];revisions=[]
            def submit(role: str, command_type: str, payload: dict,
                       operation_id: str) -> dict:
                params={'command_type': command_type, 'payload': payload,
                        'operation_id': operation_id}
                reply=None
                for attempt in range(3):
                    try:
                        reply=bridge(ports[role], token, 'item.command', params,
                                     timeout=60.0)
                        break
                    except (OSError, RuntimeError, ValueError, KeyError) as exc:
                        if attempt==2:
                            raise RuntimeError(
                                f'item.command transport failure {operation_id}: {exc}')
                        time.sleep(1.0)
                command_result=reply.get('item_command', {})
                details=command_result.get('details', {})
                entry={'role': role, 'command_type': command_type,
                       'operation_id': operation_id,
                       'ok': bool(command_result.get('success', False)),
                       'error_code': command_result.get('error_code', '')}
                entry.update(replay=bool(details.get('replay', False)),
                             revision_before=details.get('item_graph_revision_before'),
                             revision_after=details.get('item_graph_revision_after'))
                return entry
            logical={role: automation(role).get('logical_player_id') for role in ('a','b')}
            index=0
            # Unique operation_id per attempt; retries reuse the same
            # operation_id and can only ever produce an idempotent replay.
            # Keep issuing fresh commands until >=24 non-replay durable
            # commits are recorded (bounded by 60 attempts overall).
            while sum(1 for e in results if e['ok'] and not e['replay']) < 24 \
                    and index < 60:
                role=('a','b')[index%2]
                if index%2==0:
                    spec=('inventory.select_hotbar',
                          {'selected_hotbar_index': (index//2)%8})
                else:
                    spec=('inventory.permission_probe',
                          {'target_player_id': logical[role]})
                entry=submit(role, spec[0], spec[1],
                             f'operation/m6/r40/{manifest["run_id"]}/{role}/{index}')
                entry['index']=index;results.append(entry);index+=1
                if not entry['ok']:
                    raise RuntimeError(f'durable command rejected (not committed): {entry}')
                time.sleep(.3)
            committed=[e for e in results if e['ok'] and not e['replay']]
            if len(committed)<20:
                raise RuntimeError(f'only {len(committed)} durable commits recorded; '
                                   f'{len(results)} attempts')
            for e in results:
                if e['ok'] and not e['replay']:
                    revisions.append((e['revision_before'], e['revision_after']))
            if not all(b>a for a,b in revisions):
                raise RuntimeError(f'item graph revision did not advance per commit: {revisions}')
            # Duplicate operation_id with the identical payload must replay the
            # recorded result without mutating the world a second time.
            first=results[0]
            dup_spec=('inventory.select_hotbar',
                      {'selected_hotbar_index': (first['index']//2)%8}) \
                if first['command_type']=='inventory.select_hotbar' else \
                     ('inventory.permission_probe',
                      {'target_player_id': logical[first['role']]})
            dup=submit(first['role'], dup_spec[0], dup_spec[1], first['operation_id'])
            dup['index']='duplicate';results.append(dup)
            if not dup['ok'] or not dup['replay'] or \
               dup['revision_after']!=dup['revision_before']:
                raise RuntimeError(f'duplicate operation_id was not an idempotent replay: {dup}')
            summary={'schema':'dws.net_smooth.durable_workload.v1',
                     'commands':results,
                     'committed_durable_count':len(committed),
                     'command_types':sorted({e['command_type'] for e in committed}),
                     'duplicate_replay_idempotent':True}
            dump(root/'durable-commands.json',summary)
            manifest['phase_results'].append({'phase':'durable_workload','result':{
                'committed_durable_count':len(committed),
                'command_types':summary['command_types'],
                'duplicate_replay_idempotent':True}})
            return summary
        if args.scenario == 'r31-reconnect-roundtrip':
            # R3.1: A crosses to secondary via real movement only, B reconnects
            # mid-remote, A must stay secondary (no foreign handback), then A
            # returns to primary. Acceptance reads server-pushed authoritative
            # product seam state (region_id/epoch/crossings/roundtrips), never
            # client-side position alone. Absence of a crossing is a hard FAIL.
            def poll_r31(title: str, budget_s: float, feed: dict, accept) -> dict:
                deadline = time.monotonic() + budget_s
                last_feed = 0.0
                while True:
                    alive()
                    states = {role: automation(role) for role in ('a', 'b')}
                    if accept(states):
                        return states
                    now = time.monotonic()
                    if now - last_feed >= 0.2:
                        last_feed = now
                        for role, move in feed.items():
                            drive(role, **move)
                    if now > deadline:
                        a = states['a']
                        raise RuntimeError(
                            f'r31 stage {title} timeout; a_region={a.get("region_id")} '
                            f'a_x={a.get("local_player", {}).get("position", {}).get("x")} '
                            f'crossings={a.get("seam_crossings")}')
                    time.sleep(0.05)
            budget = max(60.0, args.duration)
            r31: dict = {'schema': 'dws.net_smooth.r31_roundtrip.v1', 'stages': {}}
            base = {role: automation(role) for role in ('a', 'b')}
            a_region0 = str(base['a'].get('region_id', ''))
            a_cross0 = int(base['a'].get('seam_crossings', 0))
            a_round0 = int(base['a'].get('seam_roundtrips', 0))
            a_epoch0 = int(base['a'].get('seam_authority_epoch', 0))
            a_own0 = int(base['a'].get('ownership_epoch', 0))
            if a_region0 != 'region/user1/a' or a_cross0 != 0 or a_round0 != 0:
                raise RuntimeError(f'r31 baseline not clean primary: region={a_region0} '
                                   f'crossings={a_cross0} roundtrips={a_round0}')
            r31['baseline'] = {'a_region': a_region0, 'a_authority_epoch': a_epoch0,
                               'a_ownership_epoch': a_own0}
            dump(root/'r31-roundtrip.json', r31)

            def crossed_to_secondary(states: dict) -> bool:
                a = states['a']
                return str(a.get('region_id', '')) != a_region0 and \
                    int(a.get('seam_crossings', 0)) > a_cross0
            sprint_feed = {'a': {'x': 1.0, 'z': 0.0, 'sprint': True},
                           'b': {'x': 0.0, 'z': 0.0}}
            secondary = poll_r31('a_to_secondary', budget, sprint_feed, crossed_to_secondary)
            sec = secondary['a']
            sec_region = str(sec.get('region_id', ''))
            sec_epoch = int(sec.get('seam_authority_epoch', 0))
            sec_cross = int(sec.get('seam_crossings', 0))
            sec_own = int(sec.get('ownership_epoch', 0))
            # Authoritative crossing, not just a client-side position change:
            # the region push must carry a bumped authority epoch.
            if sec_epoch <= a_epoch0:
                raise RuntimeError(f'r31 crossing not authoritative: epoch {a_epoch0}->{sec_epoch}')
            # A must remain simulatable under secondary movement authority.
            sec_x0 = float(sec['local_player']['position']['x'])
            moved = poll_r31('a_secondary_movement', 10.0, sprint_feed,
                             lambda st: abs(float(st['a']['local_player']['position']['x']) - sec_x0) > 0.5)
            r31['stages']['a_secondary'] = {
                'region_id': sec_region, 'authority_epoch': sec_epoch,
                'crossings': sec_cross, 'ownership_epoch': sec_own,
                'position': secondary['a']['local_player']['position'],
                'movement_continues': True}
            dump(root/'r31-roundtrip.json', r31)

            # B reconnects while A is remote. A must not be force-returned or
            # handed back on B's behalf; only B's own ownership epoch advances.
            b_before = automation('b')
            reconnect = command('b', 'network.reconnect')
            time.sleep(1)
            wait_ready('b')
            b_after = automation('b')
            if int(b_after.get('ownership_epoch', 0)) <= int(b_before.get('ownership_epoch', 0)):
                raise RuntimeError('r31 B reconnect did not advance ownership epoch')
            a_now = automation('a')
            if str(a_now.get('region_id', '')) != sec_region or \
               int(a_now.get('seam_crossings', 0)) != sec_cross or \
               int(a_now.get('seam_authority_epoch', 0)) != sec_epoch or \
               int(a_now.get('ownership_epoch', 0)) != sec_own:
                raise RuntimeError(f'r31 B reconnect disturbed remote A: {a_now}')
            # B stays simulatable right after reconnect. The client may stall
            # for seconds while rebuilding its session, so poll with real
            # movement input instead of a fixed sleep.
            bpos0 = b_after.get('local_player', {}).get('position', {})
            def b_moved(states: dict) -> bool:
                p = states['b'].get('local_player', {}).get('position', {})
                return abs(float(p.get('z', 0.0)) - float(bpos0.get('z', 0.0))) >= 0.2
            poll_r31('b_post_reconnect_movement', 30.0,
                     {'a': {'x': 0.0, 'z': 0.0}, 'b': {'x': 0.0, 'z': -1.0}}, b_moved)
            r31['stages']['b_reconnect'] = {
                'b_epoch_before': int(b_before.get('ownership_epoch', 0)),
                'b_epoch_after': int(b_after.get('ownership_epoch', 0)),
                'a_region_unchanged': True, 'a_authority_epoch': sec_epoch}
            dump(root/'r31-roundtrip.json', r31)

            def returned_to_primary(states: dict) -> bool:
                a = states['a']
                return str(a.get('region_id', '')) == a_region0 and \
                    int(a.get('seam_roundtrips', 0)) > a_round0
            return_feed = {'a': {'x': -1.0, 'z': 0.0, 'sprint': True},
                           'b': {'x': 0.0, 'z': 0.0}}
            primary = poll_r31('a_to_primary', budget, return_feed, returned_to_primary)
            prim = primary['a']
            prim_epoch = int(prim.get('seam_authority_epoch', 0))
            if prim_epoch <= sec_epoch:
                raise RuntimeError(f'r31 return not authoritative: epoch {sec_epoch}->{prim_epoch}')
            r31['stages']['a_primary_return'] = {
                'region_id': a_region0, 'authority_epoch': prim_epoch,
                'roundtrips': int(prim.get('seam_roundtrips', 0)),
                'ownership_epoch': int(prim.get('ownership_epoch', 0)),
                'position': prim['local_player']['position']}
            dump(root/'r31-roundtrip.json', r31)
            manifest['phase_results'].append({'phase': 'r31_reconnect_roundtrip',
                                              'result': r31['stages']})
            # Functional r31 stages (including B's mid-remote reconnect) are
            # complete; only now open the normative perf window.
            for role in processes: (root/role/'measure.start').touch()
            # The earlier r31 authority/remote-owner roundtrip is FUNCTIONAL
            # coverage, not part of the 120s normative movement frame window.
            # Reset the loop clock here or a slow roundtrip shortens/erases
            # the measured interval despite a fresh measure.start marker.
            started = time.monotonic()
        def standard_phase_loop() -> None:
            last_phase=-1;phase_states={}
            while time.monotonic()-started < args.duration:
                alive();elapsed=time.monotonic()-started
                # 8 phases: A observer/B moving, reverse, simultaneous straight,
                # strafe, circle, turn-only, sprint, stop/start. No position setters.
                phase=int(elapsed//8)%8
                phase_changed=phase!=last_phase
                if phase_changed:
                    for role in ('a','b'):
                        phase_states[role]=bridge(ports[role],token,'state.get',{'kind':'automation'})
                for role in ('a','b'):
                    x,z,yaw,sprint=0.0,-1.0,0.0,False
                    if phase==0 and role=='a': z=0.0
                    if phase==1 and role=='b': z=0.0
                    if phase==3: x,z=1.0,0.0
                    if phase==4: yaw=(elapsed*.6)%(2*math.pi)
                    if phase==5: z=0.0;yaw=(elapsed*.9)%(2*math.pi)
                    if phase==6: sprint=True
                    if phase==7: z=-1.0 if int(elapsed*2)%2==0 else 0.0
                    if role=='b': x=-x;z=-z
                    if args.scenario=='local':
                        # Stay in primary; do not conflate network smoothness with
                        # the separate USER1 remote-owner reconnect restriction.
                        # Feedback only at phase boundaries, through read-only state.
                        pos=phase_states[role]['automation']['local_player']['position']
                        toward_z=1.0 if pos['z']>0 else -1.0
                        if phase in (0,1,2,6,7) and z: z=toward_z
                        if phase==3: x=.2 if pos['x'] < -7 else -.2
                        if phase==4: z=.4;yaw=(elapsed*math.pi)%(2*math.pi)
                    bridge(ports[role],token,'movement.set',{'move_x':x,'move_z':z,
                        'look_yaw':yaw,'sprint':sprint,'ttl_ms':900})
                if phase_changed:
                    entry={'elapsed_s':elapsed,'phase':phase,**phase_states}
                    with (root/'phases.jsonl').open('a',encoding='utf-8') as stream:
                        stream.write(json.dumps(entry,ensure_ascii=False)+'\n')
                    last_phase=phase
                time.sleep(.2)
        if args.scenario == 'r31-reconnect-roundtrip':
            # Keep a full measurement window after the roundtrip stages so the
            # same GUI run also carries complete perf coverage.
            standard_phase_loop()
        elif args.scenario == 'r3-slow-item':
            # Concurrent automation control: both users keep issuing movement
            # while 24 real ITEM commands pass through the exact M6 writer.
            # Close the perf window before the end-of-run reconnect.
            stop_feed = threading.Event()
            feed_errors: list[str] = []
            def feed_both_players() -> None:
                while not stop_feed.is_set():
                    for role, x in (('a', 1.0), ('b', -1.0)):
                        try:
                            drive(role, x, 0.0, sprint=False)
                        except (OSError, RuntimeError, ValueError, KeyError) as exc:
                            feed_errors.append(f'{role}: {exc}')
                            stop_feed.set()
                            return
                    stop_feed.wait(.20)
            feeder = threading.Thread(target=feed_both_players, daemon=True)
            feeder.start()
            try:
                durable_phase()
            finally:
                stop_feed.set()
                feeder.join(timeout=10)
            if feed_errors:
                raise RuntimeError(f'concurrent R3 feed failed: {feed_errors[:3]}')
            standard_phase_loop()
            close_measure_window()
            old=bridge(ports['b'],token,'state.get',{'kind':'automation'})['automation']
            reconnect=command('b','network.reconnect')
            time.sleep(1);wait_ready('b')
            after=bridge(ports['b'],token,'state.get',{'kind':'automation'})['automation']
            manifest['phase_results'].append({'phase':'r3_reconnect_b','result':reconnect,
                                             'before_epoch':old.get('ownership_epoch'),
                                             'after_epoch':after.get('ownership_epoch')})
            if after.get('ownership_epoch',0)<=old.get('ownership_epoch',0):
                raise RuntimeError('R3 reconnect did not advance ownership epoch')
        elif args.scenario == 'durable-commands':
            # Durable commands run inside the measured window; the standard
            # movement loop afterwards keeps full movement/perf coverage.
            durable_phase()
            standard_phase_loop()
            close_measure_window()
            old=bridge(ports['b'],token,'state.get',{'kind':'automation'})['automation']
            reconnect=command('b','network.reconnect')
            time.sleep(1);wait_ready('b')
            after=bridge(ports['b'],token,'state.get',{'kind':'automation'})['automation']
            manifest['phase_results'].append({'phase':'reconnect_b','result':reconnect,
                                             'before_epoch':old.get('ownership_epoch'),'after_epoch':after.get('ownership_epoch')})
            if after.get('ownership_epoch',0)<=old.get('ownership_epoch',0):
                raise RuntimeError('reconnect did not advance ownership epoch')
        elif args.scenario in ('local', 'seam-stress'):
            standard_phase_loop()
            close_measure_window()
            # Reconnect is outside the perf window; it still must execute and recover.
            old=bridge(ports['b'],token,'state.get',{'kind':'automation'})['automation']
            reconnect=command('b','network.reconnect')
            time.sleep(1);wait_ready('b')
            after=bridge(ports['b'],token,'state.get',{'kind':'automation'})['automation']
            manifest['phase_results'].append({'phase':'reconnect_b','result':reconnect,
                                             'before_epoch':old.get('ownership_epoch'),'after_epoch':after.get('ownership_epoch')})
            if after.get('ownership_epoch',0)<=old.get('ownership_epoch',0):
                raise RuntimeError('reconnect did not advance ownership epoch')
        if not measure_closed:
            close_measure_window()
        for role in ('a','b'):
            bridge(ports[role],token,'movement.stop')
            dump(root/role/'final-state.json',bridge(ports[role],token,'state.get',{'kind':'automation'}))
            if args.mode=='gui':
                dump(root/role/'screenshot.json',bridge(ports[role],token,'screenshot.capture',{'filename':f'{role}-final.png'}))
        manifest['completed']=True
    except Exception as exc:
        manifest['errors'].append(f'{type(exc).__name__}: {exc}')
    finally:
        # B3: Windows console-wrapper can exit leaving a Godot MAIN child.
        # Isolate by THIS RUN's unguessable instance/node IDs and Godot bin
        # directory; never taskkill other Godot sessions or unrelated projects.
        try:
            cleanup = finalize_owned_processes(
                processes, root, manifest['run_id'], args.godot)
        except Exception as exc:
            # Unexpected scanner/runtime exception is INCONCLUSIVE, not PASS.
            # Always best-effort reap only Popen handles already registered.
            cleanup = {'verified': False,
                       'errors': ['CLEANUP_EXCEPTION:' + type(exc).__name__],
                       'role_exit_codes': {}, 'exception': type(exc).__name__}
            for role, proc in processes.items():
                if proc.poll() is None:
                    try:
                        proc.kill()
                        proc.wait(timeout=10)
                    except (OSError, subprocess.TimeoutExpired):
                        cleanup['errors'].append(f'{role}: EMERGENCY_KILL_FAILED')
                cleanup['role_exit_codes'][role] = proc.poll()
        manifest['cleanup'] = cleanup
        manifest['process_exit_codes'].update(cleanup.get('role_exit_codes', {}))
        manifest['errors'].extend(cleanup.get('errors', []))
        if not bool(cleanup.get('verified', False)):
            manifest['errors'].append('NET_SMOOTH_RUN_PROCESS_ISOLATION_UNVERIFIED')
        for stream in streams:
            try:
                stream.close()
            except OSError:
                manifest['errors'].append('RUNTIME_LOG_CLOSE_FAILED')
        for role in processes:
            try:
                text=(root/role/'runtime.log').read_text(encoding='utf-8',
                                                        errors='replace')
                errors=[line for line in text.splitlines()
                        if any(e in line for e in BAD_LOG)]
                if errors:
                    manifest['errors'].append(f'{role}: runtime error lines ({len(errors)})')
                    (root/role/'errors.txt').write_text(
                        '\n'.join(errors),encoding='utf-8')
            except OSError:
                manifest['errors'].append(f'{role}: RUNTIME_LOG_MISSING')
        dump(root/'manifest.json',manifest)


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument('--godot',required=True,type=Path)
    parser.add_argument('--mode',choices=('focused','headless','gui'),default='focused')
    parser.add_argument('--output',type=Path)
    parser.add_argument('--duration',type=float,default=120)
    parser.add_argument('--warmup',type=float,default=20)
    parser.add_argument('--startup-timeout',type=float,default=240)
    parser.add_argument('--test-timeout',type=float,default=240)
    parser.add_argument('--include-process-tests',action='store_true')
    parser.add_argument('--skip-import',action='store_true')
    parser.add_argument('--profile',default='LOCAL')
    parser.add_argument('--scenario',choices=('local','seam-stress','r31-reconnect-roundtrip','durable-commands','r3-slow-item'),default='local')
    parser.add_argument('--slow-item-writer-ms',type=int,default=0,
                        help='Test-only delayed ITEM worker in milliseconds (max 2000)')
    parser.add_argument('--checkpoint-mode',choices=('async','sync'),default='async')
    parser.add_argument('--r3c-async-admission',action='store_true',
                        help='Opt-in R3C bounded JOIN queue and async durable LEAVE')
    parser.add_argument('--r3c2-avatar-prewarm',action='store_true',
                        help='Opt-in bounded Quaternius visual prewarm/reuse before JOIN_ACK')
    parser.add_argument('--r3c2-server-phased',action='store_true',
                        help='Opt-in exact-M6-gated ITEM postcommit publication across server frames')
    parser.add_argument('--r3c3-staged-earth',action='store_true',
                        help='Client-only staged Earth geometry and R2 vegetation')
    parser.add_argument('--r3c21-frame-paced-presentation', action='store_true',
                        help='R3C3 R2.1: preattach hidden vegetation nodes per frame before atomic visual swap')
    parser.add_argument('--r3c4-periodic-frame-pacing', action='store_true',
                        help='R3C.4: defer a due periodic checkpoint off the same-frame snapshot burst (bounded 64ms)')
    parser.add_argument('--r3c4r2-worker-envelope', action='store_true',
                        help='R3C.4 R2: server-only immutable periodic envelope hashing on existing async writer')

    parser.add_argument('--r3c4r30-stage-attribution', action='store_true',
                        help='R3.0: diagnostic replay-export/checksum/deep-copy timing; requires R2')
    parser.add_argument('--r3c4r31-replay-projection', action='store_true',
                        help='R3.1a: bounded versioned replay projection; requires R2, excludes R3.0 timing')
    parser.add_argument('--r3c4r31b-durable-attribution', action='store_true',
                        help='R3.1b P0: server-only per-domain gameplay source timing, requires R3.1a')
    parser.add_argument('--r31bp1-durable-chunks', action='store_true',
                        help='R3.1b P1: server-only immutable M4/mining durable chunk cache, requires full P0 stack')
    parser.add_argument('--r31bp20-validator-attribution', action='store_true',
                        help='P2.0 server-only exact native validator stage attribution, requires P1 ON')
    parser.add_argument('--r31p22-loop-attribution', action='store_true',
                        help='P2.2: server-only exact loop/poll/compact-send stage timing, requires P1')
    parser.add_argument('--inject-stall-role',choices=('server','a','b'))
    parser.add_argument('--inject-stall-ms',type=int,default=250)
    args=parser.parse_args()
    args.godot=args.godot.resolve()
    if not args.godot.is_file(): parser.error('Godot executable not found')
    if args.duration<12 or args.warmup<0 or args.startup_timeout<=0: parser.error('invalid duration/budgets')
    if args.slow_item_writer_ms < 0 or args.slow_item_writer_ms > 2000:
        parser.error('slow ITEM writer delay must be 0..2000ms')
    if args.slow_item_writer_ms and args.scenario != 'r3-slow-item':
        parser.error('test delay only allowed in R3 slow-item scenario')
    if args.r3c21_frame_paced_presentation and not args.r3c3_staged_earth:
        parser.error('R3C21 presentation requires --r3c3-staged-earth')
    if args.r3c4r2_worker_envelope and not args.r3c4_periodic_frame_pacing:
        parser.error('R3C4 R2 worker envelope requires --r3c4-periodic-frame-pacing')

    if args.r3c4r30_stage_attribution and not args.r3c4r2_worker_envelope:
        parser.error('R3C4 R3.0 attribution requires --r3c4r2-worker-envelope')
    if args.r3c4r31_replay_projection and not args.r3c4r2_worker_envelope:
        parser.error('R3C4 R3.1 replay projection requires --r3c4r2-worker-envelope')
    if args.r3c4r31_replay_projection and args.r3c4r30_stage_attribution:
        parser.error('R3C4 R3.1 cache excludes R3.0 uncached attribution')
    if args.r3c4r31b_durable_attribution and not args.r3c4r31_replay_projection:
        parser.error('R3C4 R3.1b durable attribution requires --r3c4r31-replay-projection')
    if args.r31bp1_durable_chunks and not (
        args.r3c4r31b_durable_attribution and args.r3c4r31_replay_projection
        and args.r3c4r2_worker_envelope and args.r3c4_periodic_frame_pacing
        and args.r3c_async_admission
    ):
        parser.error('R31b P1 durable chunks require the full P0 stack '
                     '(--r3c4r31b-durable-attribution --r3c4r31-replay-projection '
                     '--r3c4r2-worker-envelope --r3c4-periodic-frame-pacing --r3c-async-admission)')
    if args.r31bp20_validator_attribution and not args.r31bp1_durable_chunks:
        parser.error('P2.0 validator attribution requires --r31bp1-durable-chunks')
    if args.r31p22_loop_attribution and not args.r31bp1_durable_chunks:
        parser.error('P2.2 server-loop stage attribution requires --r31bp1-durable-chunks')
    run_id=uuid.uuid4().hex[:16]
    args.output=(args.output or ROOT/'artifacts/net-smooth1'/run_id).resolve()
    args.output.mkdir(parents=True,exist_ok=False)
    manifest={'schema':'dws.net_smooth.run.v1','run_id':run_id,'mode':args.mode,
              'duration_s':args.duration,'profile':args.profile,'identity':identity(args.godot),
              'started_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
    dump(args.output/'manifest.json',manifest)
    print(f'NET-SMOOTH1 output: {args.output}',flush=True)
    if not args.skip_import: import_project(args.godot,args.output,args.startup_timeout)
    if args.mode=='focused':
        tests=TESTS+(PROCESS_TESTS if args.include_process_tests else [])
        results=[]
        for script in tests:
            result=run_script(args.godot,script,args.output,args.test_timeout);results.append(result)
            print(('PASS ' if result['passed'] else 'FAIL ')+script,flush=True)
            dump(args.output/'focused.json',{'identity':manifest['identity'],'tests':results,
                                            'complete':len(results)==len(tests)})
        return 0 if all(x['passed'] for x in results) else 1
    play(args,manifest)
    report=write_report(args.output)
    print(f'{report["verdict"]} / {report["evidence_class"]}; {args.output/"report.json"}',flush=True)
    return {'PASS':0,'FAIL':1,'INCONCLUSIVE':2}[report['verdict']]

if __name__=='__main__':
    raise SystemExit(main())
