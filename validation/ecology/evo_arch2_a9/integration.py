"""Real A8 biology/ownership, A9 representations and anchored persistence."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from scripts.research.ecology.v2.ecological_fidelity_v1 import FidelityRecord, FidelityError, RefinementRequired, canonical, digest, aggregate, require, MODES
from scripts.research.ecology.v2.fidelity_runtime_v1 import NativeA8
from scripts.research.ecology.v2 import snapshot_store as S


def command(record, kind='ADVANCE', args=None, actor=None, epoch=None):
    c = record.source()
    return {'op_id': 'a9.op.%d' % c['revision'], 'kind': kind, 'actor': actor or c['owner_id'],
            'epoch': c['owner_epoch'] if epoch is None else epoch, 'revision': c['revision'],
            'clock': c['clock'] + 1, 'args': {} if args is None else args}


def handoff(backend, record, target):
    src = record.source(); epoch = src['owner_epoch']; before = src['ecology_sha256']
    ticket = {'schema': 'planet_simulator.handoff_ticket.v1', 'protocol_version': 1,
              'ticket_id': 'a9.ticket.%d' % epoch, 'entity_id': src['entity_id'], 'region_id': src['region_id'],
              'source_node_id': src['owner_id'], 'target_node_id': target,
              'source_authority_epoch': epoch, 'target_authority_epoch': epoch + 1,
              'expected_state_revision': src['revision'], 'created_at_tick': src['clock'] + 1,
              'expires_at_tick': src['clock'] + 100, 'state': 'REQUESTED', 'snapshot_id': '', 'snapshot_hash': '',
              'transition_revision': 0, 'reason': ''}
    current = backend.step(record, command(record, 'BEGIN', {'ticket': ticket}))
    for index, state in enumerate(('PREPARING', 'FROZEN', 'SNAPSHOT_READY', 'TARGET_PREPARED', 'COMMITTED')):
        current = current.convert('REDUCED' if index % 2 == 0 else 'FULL')
        cut = json.loads(current.execution_snapshot())['cut']; t = cut['ticket']
        ack = state == 'TARGET_PREPARED'
        cmd = command(current, 'TRANSITION', {'ticket_id': t['ticket_id'], 'state': state,
                      'payload_hash': t['snapshot_hash'] if ack else ''}, target if ack else None, epoch + 1 if ack else None)
        received = cut['ecology_payload'].encode() if ack else b''
        current = backend.step(current, cmd, received)
        require(current.source()['ecology_sha256'] == before, 'HANDOFF_CHANGED_BIOLOGY')
    require(current.source()['owner_id'] == target and current.source()['owner_epoch'] == epoch + 1, 'HANDOFF_OWNER')
    return current


def anchor_write(path, anchor):
    raw = canonical(S.validate_anchor(anchor))
    temp = path.with_suffix('.tmp')
    with temp.open('wb') as f:
        f.write(raw); f.flush(); os.fsync(f.fileno())
    os.replace(temp, path)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try: os.fsync(fd)
    finally: os.close(fd)
    require(path.read_bytes() == raw, 'EXTERNAL_ANCHOR_WRITE')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--restore', type=Path)
    parser.add_argument('--sha'); parser.add_argument('--origin')
    args = parser.parse_args()
    out = ROOT / 'artifacts/a9/integration'
    if args.restore:
        backend = NativeA8(ROOT, args.godot, ROOT / 'artifacts/a9/restarts')
        record = backend.restore(args.restore.read_bytes(), args.sha, args.origin)
        print('A9_RESTORE_PASS mode=' + record.mode + ' sha=' + record.sha256)
        return 0
    if out.exists(): shutil.rmtree(out)
    out.mkdir(parents=True)
    result = {'verdict': 'FAIL', 'checks': [], 'scope': 'BOUNDED_FIDELITY_NOT_COARSE_POPULATION_DYNAMICS'}
    backend = NativeA8(ROOT, args.godot, out / 'native')
    def passed(name):
        result['checks'].append(name); print('PASS ' + name, flush=True)
    try:
        full = backend.genesis('a9.primary', steps=4)
        require(full.source()['ecology_step'] == 4 and full.totals()['counts']['corpses'] > 0, 'REAL_CORPSE_FIXTURE')
        initial_packet = full
        cmd = command(full)
        f_next = backend.step(full, cmd)
        r_next = backend.step(full.convert('REDUCED'), cmd)
        require(f_next.execution_snapshot() == r_next.execution_snapshot(), 'REDUCED_NATIVE_CONTINUATION')
        passed('full_reduced_native_continuation_exact')
        for mode in MODES:
            record = full.convert(mode); before = record.data
            for lod in ('DETAIL', 'SUMMARY', 'HIDDEN'): record.render_view(lod)
            require(record.data == before and record.source() == full.source(), 'RENDER_MUTATED_BIOLOGY')
            require(record.totals() == full.totals(), 'MODE_CONSERVATION')
            if mode in ('PATCH', 'AGGREGATE'):
                runs = len(backend.runs)
                try: backend.step(record, cmd)
                except RefinementRequired: pass
                else: raise FidelityError('LOSSY_EXECUTION_ACCEPTED')
                require(len(backend.runs) == runs, 'HIDDEN_REFINEMENT_WORK')
            refined = record.refine(full.execution_snapshot(), backend.admit)
            require(refined.data == full.data, 'HISTORICAL_REFINEMENT')
            passed('mode_' + mode.lower() + '_conservation_render_refinement')
        b = handoff(backend, r_next, 'node.b')
        try: backend.step(b, command(b, actor='node.a', epoch=1))
        except FidelityError: pass
        else: raise FidelityError('OLD_OWNER_ACCEPTED')
        a = handoff(backend, b, 'node.a')
        require(a.source()['owner_epoch'] == 3 and a.source()['ecology_sha256'] == r_next.source()['ecology_sha256'], 'ROUNDTRIP_SEAM')
        passed('real_a_b_a_seam_preserves_biology_and_fences_old_owner')
        store = S.SnapshotStore.initialize(out / 'store')
        external = out / 'caller-owned-anchor.json'
        acknowledged = S.genesis_anchor(); anchor_write(external, acknowledged)
        stale = None
        for mode in MODES:
            record = a.convert(mode)
            previous = acknowledged
            acknowledged = store.commit(previous, record.data, lambda raw: FidelityRecord.restore(raw, record.sha256, record.source()['origin_sha256']).data == record.data)
            anchor_write(external, acknowledged)
            loaded_head, loaded = S.SnapshotStore(store.root).load(json.loads(external.read_bytes()))
            require(loaded_head == acknowledged and loaded == record.data, 'DURABLE_PACKET')
            packet_path = out / (mode.lower() + '.json'); packet_path.write_bytes(loaded)
            cli = [sys.executable, str(Path(__file__)), '--godot', str(args.godot), '--restore', str(packet_path),
                   '--sha', record.sha256, '--origin', record.source()['origin_sha256']]
            log = out / (mode.lower() + '-restart.log')
            with log.open('wb') as f:
                p = subprocess.run(cli, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT, timeout=600, check=False)
            text = log.read_text()
            require(p.returncode == 0 and 'A9_RESTORE_PASS mode=' + mode + ' sha=' + record.sha256 in text, 'FRESH_PROCESS_RESTORE:' + text[-2000:])
            if stale is None: stale = previous
            passed('durable_fresh_process_' + mode.lower())
        try: store.commit(stale, initial_packet.data, lambda raw: raw == initial_packet.data)
        except S.Conflict: pass
        else: raise FidelityError('STALE_DURABLE_PACKET_ACCEPTED')
        require(store.load(acknowledged)[0] == acknowledged, 'STALE_WRITE_MOVED_TIP')
        passed('stale_representation_cannot_overwrite_new_durable_cut')
        paid = backend.genesis('a9.paid', steps=16)
        require(paid.totals()['counts']['pending_propagules'] > 0, 'NO_REAL_PAID_PROPAGULES')
        for mode in MODES: require(paid.convert(mode).totals() == paid.totals(), 'PAID_OUTBOX_CONSERVATION')
        passed('real_funded_propagules_and_corpses_not_double_counted')
        members = [backend.genesis('a9.scale.%d' % i).convert('AGGREGATE') for i in range(8)]
        batch = aggregate(members)
        require(batch == aggregate(reversed(members)), 'SCALE_ORDER')
        require(json.loads(batch)['totals']['counts']['living'] == sum(r.totals()['counts']['living'] for r in members), 'SCALE_COUNTS')
        for duplicate in (members[0], members[0].convert('AGGREGATE')):
            try: aggregate([*members, duplicate])
            except FidelityError: pass
            else: raise FidelityError('DUPLICATE_SCALE_PARTITION')
        passed('eight_real_partitions_aggregation_no_overlap')
        result.update(verdict='PASS', source=full.source(), paid_source=paid.source(), final_source=a.source(),
                      native_processes=backend.runs, modes=list(MODES),
                      retained_packet_bytes={mode: len(paid.convert(mode).data) for mode in MODES},
                      real_scale={'partitions': 8, 'living': json.loads(batch)['totals']['counts']['living'],
                                  'aggregate_bytes': len(batch), 'claim': 'REPRESENTATION_NOT_ACTIVE_SIMULATION_THROUGHPUT'},
                      durable_anchor=acknowledged)
        require(len(result['checks']) == 13, 'INTEGRATION_CHECK_COUNT')
        print('EVO_ARCH2_A9_INTEGRATION checks=13 failed=0', flush=True)
        return 0
    except Exception as exc:
        result['error'] = str(exc); result['native_processes'] = backend.runs
        print('A9_INTEGRATION_FAILURE: ' + str(exc), flush=True)
        return 1
    finally:
        (out / 'summary.json').write_bytes(canonical(result))


if __name__ == '__main__':
    raise SystemExit(main())
