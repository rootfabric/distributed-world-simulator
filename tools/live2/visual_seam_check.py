"""Two-GUI visual seam check via the repository LIVE2 automation bridge.

PNG sampling establishes visibility and animation changes, not frame p99.
All process handles, ports and profiles belong to this invocation.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import secrets
import socket
import subprocess
import time

from live2_automation_client import request


def require(condition, code):
    """Acceptance checks must also execute under python -O/PYTHONOPTIMIZE."""
    if not condition:
        raise AssertionError(code)


class VisualCheck:
    def __init__(self, args):
        self.args = args
        self.project = args.project.resolve()
        self.root = args.output.resolve() / time.strftime('%Y%m%d-%H%M%S')
        self.root.mkdir(parents=True)
        self.head = self.git('rev-parse', 'HEAD').strip()
        self.profile = json.loads((self.project / 'config/release/playtest-r1.json').read_text())
        self.token = secrets.token_hex(32)
        self.port = self.free_port(socket.SOCK_DGRAM)
        self.ports = {'a': self.free_port(), 'b': self.free_port()}
        while self.ports['a'] == self.ports['b']:
            self.ports['b'] = self.free_port()
        self.processes, self.logs, self.samples = {}, [], []
        self.report = {
            'schema': 'dws.visual_seam_check.v1', 'result': 'RUNNING',
            'head': self.head, 'tree': self.git('rev-parse', 'HEAD^{tree}').strip(),
            'profile': self.profile['id'], 'phases': [],
            'engine_sha256': self.digest(args.godot),
            'runner_sha256': self.digest(Path(__file__)),
            'limitations': ['localhost product seam', 'PNG sampling affects rendering',
                            'anchors do not prove lack of occlusion', 'no frame p99 verdict'],
        }
        (self.root / 'runner.py').write_bytes(Path(__file__).read_bytes())
        self.save('report.json', self.report)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.project), *args], text=True)

    @staticmethod
    def digest(path):
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()

    @staticmethod
    def free_port(kind=socket.SOCK_STREAM):
        with socket.socket(socket.AF_INET, kind) as sock:
            sock.bind(('127.0.0.1', 0))
            return sock.getsockname()[1]

    def save(self, name, value):
        (self.root / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

    def rpc(self, role, method, params=None):
        reply = request(self.ports[role], self.token, method, params or {}, timeout=10)
        if not reply.get('ok'):
            raise RuntimeError(str(reply))
        return reply['result']

    def command(self, role, line):
        return self.rpc(role, 'command.execute', {'line': line})['result']['details']

    def state(self, role):
        return self.rpc(role, 'state.get', {'kind': 'automation'})['automation']

    def move(self, role, x=0, z=0, yaw=0, pitch=0, sprint=False):
        return self.rpc(role, 'movement.set', {'move_x': x, 'move_z': z,
                        'look_yaw': yaw, 'look_pitch': pitch, 'sprint': sprint, 'ttl_ms': 900})

    def stop(self):
        for role in ('a', 'b'):
            try:
                self.rpc(role, 'movement.stop')
            except Exception:
                pass

    def wait(self, label, predicate, timeout=90):
        started = time.monotonic()
        last = ''
        while time.monotonic() - started < timeout:
            try:
                result = predicate()
                if result:
                    self.report['phases'].append({'name': label, 'seconds': time.monotonic() - started})
                    self.save('report.json', self.report)
                    print(label, 'OK', flush=True)
                    return result
            except (OSError, RuntimeError, KeyError) as error:
                last = str(error)
            time.sleep(.2)
        raise RuntimeError(label + ' TIMEOUT ' + last)

    def spawn(self, role):
        folder = self.root / role
        folder.mkdir()
        env = {k: v for k, v in os.environ.items() if not k.startswith('DWS_NET_')}
        env.update(BREAKPOINT_RUNTIME_DISABLED='1', APPDATA=str(folder), LOCALAPPDATA=str(folder))
        env.update(self.profile['server_environment' if role == 'server' else 'client_environment'])
        env.update({k: '0' for k in self.profile['disabled_environment']})
        args = [str(self.args.godot), '--path', str(self.project), '--max-fps', '60', '--disable-vsync']
        args += ['--headless'] if role == 'server' else ['--rendering-driver', 'opengl3', '--resolution', '960x640']
        args += ['--', '--network-mvp', '--world=earth',
                 '--role=' + ('dedicated-server' if role == 'server' else 'game-client'),
                 '--server-address=127.0.0.1', f'--server-port={self.port}',
                 '--network-build-id=' + self.profile['network_build_id'],
                 '--network-git-commit=' + self.head, '--network-debug', '--node-id=visual-' + role]
        if role == 'server':
            args += ['--product-seam', '--persistence-root=' + str(self.root / 'world')]
        else:
            args += ['--player-identity=' + role, '--automation-control',
                     '--automation-control-token=' + self.token,
                     '--automation-control-port=' + str(self.ports[role]),
                     '--automation-control-output-dir=' + str(folder / 'frames')]
        info = subprocess.STARTUPINFO()
        info.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        info.wShowWindow = 0
        log = (folder / 'runtime.log').open('w', encoding='utf-8')
        self.logs.append(log)
        self.processes[role] = subprocess.Popen(args, cwd=self.project, env=env,
                                                stdout=log, stderr=subprocess.STDOUT, startupinfo=info)
        self.save('processes.json', {k: v.pid for k, v in self.processes.items()})

    def avatar_ready(self):
        avatar = self.command('a', 'character.remote.status')['remote_players'].get('b', {})
        return (avatar.get('ready') and avatar.get('asset_mode') in ('QUATERNIUS_RETARGET', 'QUATERNIUS_EMBEDDED')
                and not avatar.get('legacy_capsule_visible', True))

    def sample(self, phase):
        sample_started = time.monotonic()
        actor, observer = self.state('b'), self.state('a')
        p, q = actor['local_player']['position'], observer['local_player']['position']
        dx, dz = p['x'] - q['x'], p['z'] - q['z']
        # Godot positive yaw rotates the -Z forward axis toward -X.
        self.move('a', yaw=-math.atan2(dx, -dz), pitch=-math.atan2(.75, math.hypot(dx, dz)))
        time.sleep(.06)  # Allow a render update before observing/capturing.
        visual = self.command('a', 'character.remote.visual')['players'].get('b', {})
        frame = self.rpc('a', 'screenshot.capture', {'filename': f'{len(self.samples):04d}-{phase}.png'})
        row = {'index': len(self.samples), 'phase': phase, 'sample_started_monotonic': sample_started,
               'captured_at_monotonic': time.monotonic(),
               'actor': actor, 'observer': observer, 'visual': visual,
               'frame': str(Path(frame['path']).relative_to(self.root)),
               'frame_sha256': self.digest(frame['path'])}
        self.samples.append(row)
        self.save('samples.json', self.samples)
        require(actor['connection_state'] == observer['connection_state'] == 'CONNECTED', 'CONNECTION_LOST')
        require(actor['player_entity_id'] == self.identity and actor['ownership_epoch'] == self.epoch, 'ACTOR_IDENTITY_CHANGED')
        require(visual.get('available') and visual.get('visible_in_tree'), 'AVATAR_UNAVAILABLE')
        require(visual.get('anchors_in_frame'), 'AVATAR_OUT_OF_FRAME')
        return actor

    def idle(self, phase):
        self.stop()
        time.sleep(.7)  # Let the final movement snapshot reach the presenter.
        for _ in range(8):
            self.sample(phase)

    def crossing(self, phase, direction, sprint, region):
        started = time.monotonic()
        initial = self.state('b')
        while time.monotonic() - started < 15:
            self.move('b', x=direction, sprint=sprint)
            state = self.sample(phase)
            # Continue past the seam to capture several frames on each side.
            x = state['local_player']['position']['x']
            if (state['region_id'] == region and state['seam_authority_epoch'] > initial['seam_authority_epoch']
                    and (x >= 14 if direction > 0 else x <= -2)):
                self.stop()
                return
        raise AssertionError('VISUAL_CROSSING_TIMEOUT ' + phase)

    def validate_samples(self):
        for phase, semantic in [('idle', 'idle'), ('walk', 'walk'), ('run', 'run'), ('stopped', 'idle')]:
            rows = [r for r in self.samples if r['phase'] == phase]
            matching = [r['visual']['animation'] for r in rows if r['visual']['animation'].get('semantic') == semantic]
            require(len(matching) >= 3, 'ANIMATION_SEMANTIC_MISSING ' + phase)
            require(all(a.get('animation_playing') and a.get('target_bone_count', 0) > 0 for a in matching), 'ANIMATION_NOT_PLAYING')
            require(len({a['target_pose_sha256'] for a in matching if a.get('target_pose_sha256')}) >= 3, 'FROZEN_TARGET_POSE ' + phase)
            require(len({a['animation_position_seconds'] for a in matching}) >= 3, 'FROZEN_ANIMATION_CLOCK ' + phase)
        require(self.state('b')['seam_roundtrips'] > self.initial_roundtrips, 'ROUNDTRIP_MISSING')

    def write_gallery(self):
        # Original PNGs, no interpolation. Playback uses sampled capture times.
        frames = [{'src': row['frame'].replace('\\', '/'), 'phase': row['phase'],
                   'region': row['actor']['region_id'], 'animation': row['visual'].get('animation', {}),
                   't': row['captured_at_monotonic']} for row in self.samples]
        payload = json.dumps(frames).replace('<', '\\u003c')
        html = '''<!doctype html><meta charset="utf-8"><title>Visual seam evidence</title>
<style>body{background:#111827;color:#e5e7eb;font:16px sans-serif;margin:24px}img{max-width:100%;max-height:72vh}input{width:70%}button{padding:8px}pre{white-space:pre-wrap}</style>
<h1>Playtest R1 — визуальная проверка</h1>
<p>Исходные PNG с реальным интервалом захвата. Это выборка кадров, не видео 60 FPS.</p>
<button id="play">▶ / пауза</button> <input id="seek" type="range" min="0" value="0"><span id="count"></span>
<p><img id="frame" alt="Captured game viewport"></p><pre id="info"></pre>
<script>const frames=PAYLOAD;let index=0,playing=false,timer;
const seek=document.getElementById('seek');seek.max=Math.max(0,frames.length-1);
function show(){if(!frames.length)return;const f=frames[index];document.getElementById('frame').src=f.src;
seek.value=index;document.getElementById('count').textContent=` ${index+1}/${frames.length}`;
document.getElementById('info').textContent=JSON.stringify({phase:f.phase,region:f.region,animation:f.animation},null,2);}
function next(){if(!playing||index>=frames.length-1){playing=false;return;}const delay=Math.max(1,(frames[index+1].t-frames[index].t)*1000);
timer=setTimeout(()=>{index++;show();next()},delay);}
seek.oninput=()=>{clearTimeout(timer);playing=false;index=Number(seek.value);show()};
document.getElementById('play').onclick=()=>{clearTimeout(timer);playing=!playing;if(index>=frames.length-1)index=0;show();next()};show();</script>'''
        (self.root / 'index.html').write_text(html.replace('PAYLOAD', payload), encoding='utf-8')

    def run(self):
        try:
            if self.args.expected_head and self.head != self.args.expected_head:
                raise RuntimeError('EXPECTED_HEAD_MISMATCH')
            dirty = self.git('status', '--porcelain', '--untracked-files=no').strip()
            if dirty:
                raise RuntimeError('TRACKED_WORKTREE_DIRTY')
            self.spawn('server')
            self.wait('server-ready', lambda: '"event":"node_ready"' in (self.root / 'server/runtime.log').read_text(errors='replace'))
            for role in ('a', 'b'):
                self.spawn(role)
            for role in ('a', 'b'):
                self.wait(role + '-connected', lambda r=role: self.state(r)['connection_state'] == 'CONNECTED')
            self.wait('avatar-ready', self.avatar_ready)
            # Midpoint vantage keeps the whole actor legible on both sides.
            def position_observer():
                position = self.state('a')['local_player']['position']
                self.move('a', x=.5 if position['x'] < 5.5 else 0,
                          z=-.5 if position['z'] < 5 else 0)
                return position['x'] >= 5.5 and position['z'] >= 5
            self.wait('observer-positioned', position_observer, 15)
            self.stop()
            time.sleep(1)
            actor = self.state('b')
            self.identity, self.epoch = actor['player_entity_id'], actor['ownership_epoch']
            self.initial_roundtrips = actor['seam_roundtrips']
            self.save('initial.json', {'a': self.state('a'), 'b': actor})
            self.idle('idle')
            self.crossing('walk', .45, False, 'region/user1/b')
            self.idle('secondary-idle')
            self.crossing('run', -1, True, 'region/user1/a')
            self.idle('stopped')
            self.validate_samples()
            self.save('final.json', {'a': self.state('a'), 'b': self.state('b')})
            self.report['result'] = 'PASS'
        except Exception as error:
            self.report.update(result='FAIL', failure=repr(error))
        finally:
            self.stop()
            for role in ('a', 'b'):
                try:
                    self.rpc(role, 'command.execute', {'line': 'app.quit'})
                except Exception:
                    pass
            time.sleep(1)
            for proc in self.processes.values():
                if proc.poll() is None:
                    proc.terminate()
                try:
                    proc.wait(10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
            for log in self.logs:
                log.close()
            errors = []
            for log in self.root.glob('*/runtime.log'):
                for line in log.read_text(errors='replace').splitlines():
                    if any(word in line for word in ('SCRIPT ERROR:', 'Parse Error:', 'Compile Error:', 'PAYLOAD_CHECKSUM_MISMATCH')):
                        errors.append({'log': str(log.relative_to(self.root)), 'line': line})
            if errors:
                self.report.update(result='FAIL', log_errors=errors)
            self.report.update(frame_count=len(self.samples), process_exit_codes={k: v.returncode for k, v in self.processes.items()})
            self.write_gallery()
            self.save('report.json', self.report)
            print(self.report['result'], self.report.get('failure', ''), self.root, flush=True)
        return 0 if self.report['result'] == 'PASS' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--godot', type=Path, default=Path('C:/Godot/godot/bin/godot.windows.editor.double.x86_64.exe'))
    parser.add_argument('--output', type=Path, default=Path('C:/distributed-world-simulator/artifacts/visual-seam-20261031'))
    parser.add_argument('--expected-head')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('This launcher currently supports Windows GUI Godot only.')
    return VisualCheck(args).run()


if __name__ == '__main__':
    raise SystemExit(main())
