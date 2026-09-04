// MCP driver v5: managed gallery run with camera passes.
//  - pads overview + 8-angle orbit (radius 55, height 28)
//  - static focus shot per pack (focus_pack via runtime_call_method)
//  - 8-angle orbit around the flagship Moon pad (radius 14, height 8)
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const PROJECT = 'C:\\distributed-world-simulator\\wp-r1';
const GODOT_BIN = 'C:\\Godot\\godot\\bin\\godot.windows.editor.double.x86_64.console.exe';
const OUT_DIR = path.join(PROJECT, 'artifacts', 'world_packs_mcp');
const GALLERY = 'res://scenes/labs/world_packs/world_packs_gallery.tscn';
const PACKS = [
  'WP-MOON-INDUSTRIAL',
  'WP-MARS-DUST',
  'WP-FROZEN',
  'WP-VOLCANIC',
  'WP-TEMPERATE',
  'WP-ALIEN-WETLAND',
];
const ORBIT_ANGLES = [0, 45, 90, 135, 180, 225, 270, 315];

fs.mkdirSync(OUT_DIR, { recursive: true });
const logStream = fs.createWriteStream(path.join(OUT_DIR, 'driver.log'), { flags: 'a' });
function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  logStream.write(line + '\n');
}

const child = spawn('npx -y breakpoint-mcp', [], {
  env: {
    ...process.env,
    GODOT_PROJECT: PROJECT,
    GODOT_BIN: GODOT_BIN,
    BREAKPOINT_TOOLSETS: 'cli,runtime,processes',
    BREAKPOINT_PRIVILEGED_GROUPS: 'code-execution',
  },
  shell: true,
  stdio: ['pipe', 'pipe', 'pipe'],
});
child.stderr.on('data', (d) => logStream.write('[server.stderr] ' + d.toString()));

let nextId = 1;
const pending = new Map();
let buffer = '';

child.stdout.on('data', (chunk) => {
  buffer += chunk.toString();
  let idx;
  while ((idx = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, idx).trim();
    buffer = buffer.slice(idx + 1);
    if (!line) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      logStream.write('[non-json] ' + line + '\n');
      continue;
    }
    if (msg.id !== undefined && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) reject(new Error(JSON.stringify(msg.error)));
      else resolve(msg.result);
    }
  }
});

function request(method, params, timeoutMs = 60000) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`timeout waiting for ${method}`));
    }, timeoutMs);
    pending.set(id, {
      resolve: (result) => {
        clearTimeout(timer);
        resolve(result);
      },
      reject: (err) => {
        clearTimeout(timer);
        reject(err);
      },
    });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}

function notify(method, params) {
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n');
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function text(result) {
  if (!result || !Array.isArray(result.content)) return '';
  return result.content.filter((c) => c.type === 'text').map((c) => c.text).join('\n');
}

function image(result) {
  if (!result || !Array.isArray(result.content)) return null;
  const img = result.content.find((c) => c.type === 'image');
  return img ? img.data : null;
}

async function tool(name, args, timeoutMs = 30000) {
  return request('tools/call', { name, arguments: args }, timeoutMs);
}

async function waitForTree(marker, timeoutMs = 90000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await sleep(2000);
    try {
      const t = await tool('runtime_get_tree', { max_depth: 3 }, 20000);
      if (text(t).includes(marker)) return true;
    } catch {
      /* bridge not up yet */
    }
  }
  return false;
}

async function shoot(file) {
  const shot = await tool('runtime_screenshot', {}, 30000);
  const b64 = image(shot);
  if (!b64) {
    log(`screenshot ${file}: NO IMAGE (${text(shot).slice(0, 150)})`);
    return false;
  }
  fs.writeFileSync(path.join(OUT_DIR, file), Buffer.from(b64, 'base64'));
  log(`screenshot saved: ${file}`);
  return true;
}

async function galleryCall(method, args) {
  let callText = '';
  for (const p of ['.', 'WorldPacksGallery', 'root/WorldPacksGallery']) {
    const call = await tool('runtime_call_method', {
      path: p,
      method,
      args,
      confirm: true,
    }, 30000);
    callText = text(call);
    log(`call ${method} path="${p}" -> ${callText.slice(0, 100).replaceAll('\n', ' ')}`);
    if (!/error|invalid|not found|fail/i.test(callText)) break;
  }
  return callText;
}

async function orbitPass(prefix, count, radius, height) {
  const results = [];
  for (let index = 0; index < count; index += 1) {
    const angle = ORBIT_ANGLES[index % ORBIT_ANGLES.length];
    await galleryCall('orbit_step', [angle, radius, height]);
    await sleep(900);
    const file = `${prefix}_orbit_${String(angle).padStart(3, '0')}.png`;
    results.push({ angle, file, shot: await shoot(file) });
  }
  return results;
}

let MANAGED_ID = '';

async function main() {
  const init = await request('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'dsh-world-packs-agent', version: '1.0' },
  }, 60000);
  log(`initialized: ${JSON.stringify(init.serverInfo ?? {})}`);
  notify('notifications/initialized', {});

  const run = await tool('godot_run_managed', { scene: GALLERY, wait_timeout_ms: 20000 }, 60000);
  const runText = text(run);
  const m = runText.match(/"id"\s*:\s*"([^"]+)"/);
  MANAGED_ID = m ? m[1] : '';
  log(`run_managed -> bridge_ready=${/bridge_ready"\s*:\s*true/.test(runText)} id=${MANAGED_ID}`);
  if (!MANAGED_ID) throw new Error('no managed id');

  const padsReady = await waitForTree('WP-ALIEN-WETLAND');
  log(`pads tree ready: ${padsReady}`);
  await sleep(3500);
  await shoot('gallery_pads.png');
  const padsOrbit = await orbitPass('gallery_pads', 8, 55, 28);

  const summary = [];
  for (const pack of PACKS) {
    const file = `focus_${pack.toLowerCase().replaceAll('-', '_')}.png`;
    await galleryCall('focus_pack', [pack]);
    await sleep(2200);
    summary.push({ pack, shot: await shoot(file) });
    if (pack === 'WP-MOON-INDUSTRIAL') {
      const orbit = await orbitPass(`focus_${pack.toLowerCase().replaceAll('-', '_')}`, 8, 14, 8);
      summary.push({ pack: `${pack}#orbit`, orbit });
    }
  }

  const stop = await tool('godot_stop', { id: MANAGED_ID, confirm: true }, 20000);
  log(`stop: ${text(stop).slice(0, 120).replaceAll('\n', ' ')}`);
  await sleep(2500);

  fs.writeFileSync(path.join(OUT_DIR, 'summary.json'), JSON.stringify(summary, null, 2));
  log('=== SUMMARY ===');
  log(`pads static+orbit shots: ${1 + padsOrbit.filter((o) => o.shot).length}/9`);
  for (const s of summary) log(`RESULT ${s.pack} shot=${s.shot ?? '(see orbit)'}`);
}

main()
  .then(() => {
    log('driver done');
    child.kill();
    process.exit(0);
  })
  .catch((err) => {
    log(`driver failed: ${err.message}`);
    child.kill();
    process.exit(1);
  });
