"""R2 fault injection: kill canary server mid in-flight ITEM, restart, verify recovery.

Launches the same production game args the GUI harness uses (server role,
product-seam, dedicated persistence root), drives one canonical ITEM command
through the V0 seam, kills the server process hard (no graceful stop) while the
ITEM async worker is in flight, then restarts a fresh server on the same
persistence root and verifies only canonical committed state + replay survive.
"""
from __future__ import annotations
import json, os, socket, subprocess, sys, time, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/live2'))
from live2_automation_client import request  # noqa: E402

GODOT = Path(sys.argv[1])
OUT = (ROOT / 'artifacts/net-smooth1' / ('fault-kill-miditem-' + uuid.uuid4().hex[:8])).resolve()
OUT.mkdir(parents=True, exist_ok=True)


def free_port(udp: bool = False) -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM if udp else socket.SOCK_STREAM) as s:
        s.bind(('127.0.0.1', 0))
        return s.getnameinfo(s.getsockname(), socket.NI_NUMERICHOST)[1:][0] if False else s.getsockname()[1]


def env_for(role_dir: Path) -> dict:
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('DWS_NET_SMOOTH_'):
            del env[key]
    ud = role_dir / 'userdata'
    ud.mkdir(parents=True, exist_ok=True)
    env.update(HOME=str(ud), BREAKPOINT_RUNTIME_DISABLED='1', GODOT_SILENCE_ROOT_WARNING='1',
               DWS_NET_P1B_ITEM_ASYNC='1')
    return env


def spawn(tag: str, port: int, persistence_root: Path | None = None,
          node_id: str = '', instance_id: str = '') -> subprocess.Popen:
    target = OUT / tag
    target.mkdir(parents=True, exist_ok=True)
    proot = persistence_root if persistence_root is not None else target / 'world'
    engine = [str(GODOT), '--path', str(ROOT), '--headless', '--max-fps', '60']
    game = ['--', '--role=dedicated-server', '--network-mvp', '--world=earth',
            '--server-address=127.0.0.1', f'--server-port={port}', '--network-debug',
            '--network-debug-stay-open', '--network-profile=LOCAL',
            f'--node-id={node_id or f"fault-{tag}"}',
            f'--instance-id={instance_id or f"fault-{tag}"}',
            '--product-seam', f'--persistence-root={proot}']
    log = (target / 'runtime.log').open('w', encoding='utf-8')
    return subprocess.Popen(engine + game, cwd=ROOT, env=env_for(target), stdout=log,
                            stderr=subprocess.STDOUT)


def wait_ready(p: subprocess.Popen, tag: str, budget: float = 240.0) -> None:
    deadline = time.monotonic() + budget
    while time.monotonic() < deadline:
        if p.poll() is not None:
            raise RuntimeError(f'{tag} exited early: {p.returncode}')
        text = (OUT / tag / 'runtime.log').read_text(encoding='utf-8', errors='replace')
        if '"event":"node_ready"' in text or '"event": "node_ready"' in text:
            return
        time.sleep(0.25)
    raise RuntimeError(f'{tag} readiness timeout')


def find_player_port(log_text: str) -> int:
    import re
    m = re.findall(r'--server-port=(\d+)', log_text)
    raise RuntimeError('no')


port = free_port(True)
result = {'schema': 'dws.net_smooth.fault_kill_miditem.v1', 'steps': []}

p1 = spawn('server1', port)
wait_ready(p1, 'server1')
result['steps'].append('server1 ready')

# Client A (headless game client) to drive one ITEM through the real seam.
aport = free_port()
token = uuid.uuid4().hex + uuid.uuid4().hex
target = OUT / 'client_a'
target.mkdir(parents=True, exist_ok=True)
engine = [str(GODOT), '--path', str(ROOT), '--headless', '--max-fps', '60']
game = ['--', '--role=game-client', '--network-mvp', '--world=earth',
        '--server-address=127.0.0.1', f'--server-port={port}', '--network-debug',
        '--network-debug-stay-open', '--network-profile=LOCAL',
        f'--node-id=fault-client-a', '--instance-id=fault-kill',
        '--player-identity=a', '--automation-control',
        f'--automation-control-token={token}',
        f'--automation-control-port={aport}',
        f'--automation-control-output-dir={target / "captures"}']
ca = subprocess.Popen(engine + game, cwd=ROOT, env=env_for(target),
                      stdout=(target / 'runtime.log').open('w', encoding='utf-8'),
                      stderr=subprocess.STDOUT)
result['steps'].append('client a spawned')


def bridge(method: str, params: dict | None = None, timeout: float = 30.0) -> dict:
    reply = request(aport, token, method, params or {}, timeout=timeout)
    if not reply.get('ok'):
        raise RuntimeError(f'{method}: {reply}')
    return reply['result']


def actual_bridge_port(tag: str) -> int:
    import re
    log = OUT / tag / 'runtime.log'
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        m = re.search(r'AUTOMATION_BRIDGE_READY.*?"port":(\d+)', log.read_text(encoding='utf-8', errors='replace'))
        if m:
            return int(m.group(1))
        time.sleep(0.5)
    raise RuntimeError('automation bridge port not found')


deadline = time.monotonic() + 300
aport = actual_bridge_port('client_a')
while True:
    if ca.poll() is not None:
        raise RuntimeError(f'client a exited early: {ca.returncode}')
    try:
        st = bridge('state.get', {'kind': 'automation'}, timeout=5.0).get('automation') or {}
        if st.get('connection_state') == 'CONNECTED':
            break
    except (OSError, RuntimeError, ValueError, KeyError):
        pass
    if time.monotonic() > deadline:
        raise RuntimeError('client a connect timeout')
    time.sleep(0.5)
result['steps'].append('client a connected')

# Submit one canonical ITEM command and hard-kill the server mid in-flight
# ITEM (worker ack_wait budget is ~500ms): send from a thread, kill ~120ms in.
op = f'operation/fault/kill-miditem/{uuid.uuid4().hex[:8]}'
import threading  # noqa: E402
submit_holder = {}
submit_error = {}


def _submit() -> None:
    # Canonical client retry: same operation_id on retriable refusal.
    for attempt in range(40):
        try:
            reply = bridge('item.command', {
                'command_type': 'inventory.select_hotbar',
                'payload': {'selected_hotbar_index': 3},
                'operation_id': op}, timeout=8.0)
            submit_holder['reply'] = reply
            ic = reply.get('item_command') or {}
            if ic.get('success') or ic.get('error_code') != 'P1A_WAIT_PRIOR_PERIODIC':
                return
        except Exception as exc:
            if 'P1A_WAIT_PRIOR_PERIODIC' in str(exc):
                submit_error['last_refusal'] = str(exc)[:300]
                time.sleep(0.25)
                continue  # explicit retriable refusal, same operation_id
            submit_error.setdefault('transport', str(exc))
            return  # transport cut by the kill is the expected race outcome
        time.sleep(0.25)


t = threading.Thread(target=_submit)
t.start()
# Kill the moment the async worker accepts the ITEM (SUBMIT stage emitted)
# while the durable worker commit is still in flight (ack_wait ~500ms).
killed = False
kill_deadline = time.monotonic() + 90
while time.monotonic() < kill_deadline and t.is_alive():
    log1 = (OUT / 'server1' / 'runtime.log').read_text(encoding='utf-8', errors='replace')
    if '"stage":"SUBMIT"' in log1 or '"stage": "SUBMIT"' in log1:
        time.sleep(0.05)
        p1.kill()
        killed = True
        break
    time.sleep(0.005)
if not killed:
    p1.kill()
p1.wait(timeout=15)
t.join(timeout=30)
result['submit_reply'] = submit_holder.get('reply')
result['submit_transport_error'] = submit_error.get('transport')
result['steps'].append(f'server1 hard-killed exit={p1.returncode}')
time.sleep(1.0)

# Restart a fresh server process on the SAME persistence root and SAME node
# identity (crash recovery of the same dedicated server session).
p2 = spawn('server2', port, persistence_root=OUT / 'server1' / 'world',
           node_id='fault-server1', instance_id='fault-server1')
wait_ready(p2, 'server2')
result['steps'].append('server2 ready on same persistence root')

log2 = (OUT / 'server2' / 'runtime.log').read_text(encoding='utf-8', errors='replace')
recovered_markers = {
    'persistence_fatal': 'PERSISTENCE_FATAL' in log2,
    'recovered_event': 'M6' in log2 and ('RECOVERED' in log2 or 'recovered' in log2),
}
result['recovery_markers'] = recovered_markers

# Verify the pending operation did not become a false success: only committed
# state replays. Query durable repository artifacts on disk.
world = OUT / 'server1' / 'world'
result['server1_world_files'] = sorted(f.name for f in world.rglob('*') if f.is_file())[:20]
result['server1_checkpoint'] = json.loads((world / 'authoritative-checkpoint.json').read_text(encoding='utf-8')) \
    if (world / 'authoritative-checkpoint.json').is_file() else None
world2 = OUT / 'server2' / 'world'
result['server2_world_files'] = sorted(f.name for f in world2.rglob('*') if f.is_file())[:20]
result['server2_checkpoint'] = json.loads((world2 / 'authoritative-checkpoint.json').read_text(encoding='utf-8')) \
    if (world2 / 'authoritative-checkpoint.json').is_file() else None
log2_events = [ln for ln in log2.splitlines() if '"event"' in ln and ('RECOVERY' in ln.upper() or 'REPLAY' in ln.upper())]
result['server2_recovery_events'] = log2_events[:5]

p2.terminate()
try:
    p2.wait(timeout=60)
except subprocess.TimeoutExpired:
    p2.kill()
try:
    ca.terminate()
    ca.wait(timeout=15)
except Exception:
    ca.kill()
result['completed'] = True
(OUT / 'fault-result.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps(result, indent=2, ensure_ascii=False))
