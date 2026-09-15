"""Synthetic contract tests only. Actual biology is covered by integration.py."""
from __future__ import annotations
import base64
import copy
import json
from pathlib import Path
import sys
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from scripts.research.ecology.v2 import ecological_fidelity_v1 as F
from scripts.research.ecology.v2.fidelity_runtime_v1 import NativeA8


def fixture(entity='fixture.partition', revision=0, epoch=1):
    origin = {'entity_id': entity, 'region_id': 'fixture.region', 'owner_id': 'node.a', 'owner_epoch': 1,
              'treatment': {}, 'experiment_hash': 'e' * 64}
    raw = F.canonical({'schema': 'dws.ecology.snapshot-seam.v1', 'origin': origin, 'commands': [],
                       'cut': {'owner_id': 'node.a', 'owner_epoch': epoch, 'revision': revision, 'clock': revision,
                               'ecology_step': 0, 'ticket': {}, 'ecology_payload': 'contract-fixture-only-' * 200}})
    origin_hash = F.digest(F.canonical(origin))
    source = F.binding(raw, F.digest(raw), origin_hash)
    patches = []
    for site in F.SITES:
        patches.append({'id': site, 'field': {'owner_token': 'field.' + site, 'owner_epoch': 1, 'revision': 0,
                                              'tick': 0, 'sha256': 'f' * 64},
                        'accounts': {'initial': {'material_mg': 100, 'water_mg': 90, 'energy_mj': 50},
                                     'external': {'material_mg': 0, 'water_mg': 0, 'energy_mj': 10},
                                     'current': {'material_mg': 90, 'water_mg': 80, 'energy_mj': 40},
                                     'sinks': {'material_mg': 10, 'water_mg': 10, 'energy_mj': 20}},
                        'field_stocks': {'water_mg': 20, 'organic_mg': 5, 'nutrient_mg': 5},
                        'counts': {'living': 1, 'dead_provenance': 1, 'corpses': 1, 'pending_propagules': 0},
                        'cohorts': [{'blueprint_hash': 'b' * 64, 'living': 1, 'dead_provenance': 1}]})
    admission = {'schema': F.ADMISSION, 'success': True, 'source': source, 'patches': patches}
    def admit(data, expected, external_origin):
        if (data, expected, external_origin) != (raw, F.digest(raw), origin_hash):
            raise F.FidelityError('FIXTURE_NOT_ADMITTED')
        return copy.deepcopy(admission)
    return raw, origin_hash, admit


def record(entity='fixture.partition', revision=0, epoch=1):
    raw, origin, admit = fixture(entity, revision, epoch)
    return F.FidelityRecord.from_snapshot(raw, F.digest(raw), origin, admit)


class FidelityTests(unittest.TestCase):
    def setUp(self):
        self.raw, self.origin, self.admit = fixture()
        self.full = record()

    def altered(self, fn, mode='PATCH'):
        doc = self.full.convert(mode).document(); fn(doc)
        return F.canonical(doc)

    def test_full_retains_exact_snapshot(self):
        self.assertEqual(self.full.execution_snapshot(), self.raw)
        self.assertEqual(self.full.source()['origin_sha256'], self.origin)

    def test_native_admission_is_required(self):
        with self.assertRaises(F.FidelityError):
            F.FidelityRecord.from_snapshot(self.raw, F.digest(self.raw), self.origin, None)
        def failed(*args):
            value = self.admit(*args); value['success'] = False; return value
        with self.assertRaises(F.FidelityError):
            F.FidelityRecord.from_snapshot(self.raw, F.digest(self.raw), self.origin, failed)

    def test_admission_source_cannot_be_rebound(self):
        def wrong(*args):
            value = self.admit(*args); value['source']['owner_epoch'] = 2; return value
        with self.assertRaisesRegex(F.FidelityError, 'NATIVE_ADMISSION_MISMATCH'):
            F.FidelityRecord.from_snapshot(self.raw, F.digest(self.raw), self.origin, wrong)

    def test_wrong_source_or_origin_rejected(self):
        for sha, origin in [('0' * 64, self.origin), (F.digest(self.raw), '0' * 64)]:
            with self.subTest(sha=sha, origin=origin):
                with self.assertRaises(F.FidelityError):
                    F.FidelityRecord.from_snapshot(self.raw, sha, origin, self.admit)

    def test_reduced_roundtrip_and_retained_bytes(self):
        reduced = self.full.convert('REDUCED')
        self.assertLess(len(reduced.data), len(self.full.data))
        self.assertEqual(reduced.execution_snapshot(), self.raw)
        self.assertEqual(reduced.convert('FULL'), self.full)
        self.assertEqual(reduced, self.full.convert('REDUCED'))

    def test_patch_is_lossy_but_preserves_fields_cohorts(self):
        patch = self.full.convert('PATCH'); doc = patch.document()
        self.assertEqual(doc['payload'], '')
        self.assertNotIn('contract-fixture-only', patch.data.decode())
        self.assertEqual(doc['projection'], self.full.document()['projection'])
        self.assertEqual(patch.source(), self.full.source())

    def test_aggregate_drops_spatial_and_cohort_details(self):
        agg = self.full.convert('AGGREGATE')
        self.assertNotIn('cohorts', agg.data.decode())
        self.assertNotIn('field.dark', agg.data.decode())
        self.assertEqual(agg.totals(), self.full.totals())
        self.assertEqual(agg.totals()['counts']['living'], 3)

    def test_all_modes_conserve_accounts(self):
        for mode in F.MODES:
            value = self.full.convert(mode)
            self.assertEqual(value.totals(), self.full.totals())
            for key in F.RESOURCES:
                a = value.totals()['accounts']
                self.assertEqual(a['initial'][key] + a['external'][key], a['current'][key] + a['sinks'][key])

    def test_lossy_execution_requires_refinement(self):
        for mode in ('PATCH', 'AGGREGATE'):
            r = self.full.convert(mode)
            with self.assertRaises(F.RefinementRequired): r.execution_snapshot()
            self.assertEqual(r.source()['ecology_step'], 0)

    def test_no_implicit_lossy_upconversion(self):
        for old, targets in [('PATCH', ('FULL', 'REDUCED')), ('AGGREGATE', ('FULL', 'REDUCED', 'PATCH'))]:
            for new in targets:
                with self.subTest(old=old, new=new):
                    with self.assertRaises(F.RefinementRequired): self.full.convert(old).convert(new)

    def test_refinement_requires_the_original_exact_bytes(self):
        for mode in F.MODES:
            self.assertEqual(self.full.convert(mode).refine(self.raw, self.admit), self.full)
        newer, _, _ = fixture(revision=1)
        for mode in ('PATCH', 'AGGREGATE'):
            with self.assertRaises(F.FidelityError): self.full.convert(mode).refine(newer, self.admit)

    def test_rehashed_forged_projection_rejected_on_refinement(self):
        def forge(d):
            d['projection']['accounts']['initial']['material_mg'] += 1
            d['projection']['accounts']['current']['material_mg'] += 1
        forged = F.FidelityRecord(self.altered(forge, 'AGGREGATE'))
        with self.assertRaisesRegex(F.FidelityError, 'REFINEMENT_PROJECTION_MISMATCH'):
            forged.refine(self.raw, self.admit)

    def test_render_options_are_not_biological_state(self):
        for mode in F.MODES:
            r = self.full.convert(mode); before = r.data
            for lod in ('DETAIL', 'SUMMARY', 'HIDDEN'):
                view = r.render_view(lod); view['source']['owner_epoch'] = 999
                if view['visible_summary']: view['visible_summary']['counts']['living'] = 999
                self.assertEqual(r.data, before)
                self.assertEqual(r.mode, mode)
            self.assertIsNone(r.render_view('HIDDEN')['visible_summary'])
            with self.assertRaises(F.FidelityError): r.render_view('PROMOTE_FULL')

    def test_packet_restore_external_anchors(self):
        for mode in F.MODES:
            r = self.full.convert(mode)
            self.assertEqual(F.FidelityRecord.restore(r.data, r.sha256, self.origin), r)
            for sha, origin in [('', self.origin), (None, self.origin), ('0'*64, self.origin), (r.sha256, '0'*64)]:
                with self.assertRaises(F.FidelityError): F.FidelityRecord.restore(r.data, sha, origin)

        # The native-service boundary is stubbed only in this contract test.
        # The real service and storage are qualified separately by integration.py.
        runtime = object.__new__(NativeA8)
        runtime.admit = self.admit
        for level in (0, 1, 6, 9):
            doc = self.full.convert('REDUCED').document()
            doc['payload'] = base64.b64encode(zlib.compress(self.raw, level)).decode()
            record = F.FidelityRecord(F.canonical(doc))
            restored = runtime.restore(record.data, record.sha256, self.origin)
            self.assertEqual(restored.data, record.data)
            self.assertEqual(restored.sha256, record.sha256)

    def test_packet_tampering_rejected(self):
        r = self.full.convert('PATCH'); changed = r.data.replace(b'node.a', b'node.b')
        with self.assertRaisesRegex(F.FidelityError, 'PACKET_ANCHOR_MISMATCH'):
            F.FidelityRecord.restore(changed, r.sha256, self.origin)

    def test_unknown_schema_keys_modes_and_encoding(self):
        for key, value in [('schema','unknown'), ('mode','FAKE'), ('encoding','fake'), ('extra',1), ('payload',False)]:
            with self.subTest(key=key):
                with self.assertRaises(F.FidelityError):
                    F.FidelityRecord(self.altered(lambda d: d.__setitem__(key, value)))

    def test_duplicate_and_noncanonical_json(self):
        r = self.full.convert('PATCH')
        duplicate = b'{"schema":"fake",' + r.data[1:]
        for raw in (duplicate, b' ' + r.data, json.dumps(r.document(), indent=2).encode()):
            with self.assertRaises(F.FidelityError): F.FidelityRecord(raw)

    def test_bool_float_negative_and_overflow_amounts(self):
        for value in (True, 1.0, -1, F.MAX_INT + 1):
            with self.subTest(value=value):
                with self.assertRaises(F.FidelityError):
                    F.FidelityRecord(self.altered(lambda d: d['projection'][0]['counts'].__setitem__('living', value)))

    def test_account_conservation_is_enforced(self):
        with self.assertRaisesRegex(F.FidelityError, 'CONSERVATION'):
            F.FidelityRecord(self.altered(lambda d: d['projection'][0]['accounts']['current'].__setitem__('water_mg', 0)))

    def test_field_time_is_bound_to_ecological_time(self):
        with self.assertRaisesRegex(F.FidelityError, 'INCONSISTENT_FIELD_CUT'):
            F.FidelityRecord(self.altered(lambda d: d['projection'][0]['field'].__setitem__('tick', 1)))

    def test_cohort_counts_and_order_enforced(self):
        for change in (lambda p: p['cohorts'][0].__setitem__('living', 0), lambda p: p['cohorts'].append(copy.deepcopy(p['cohorts'][0]))):
            with self.assertRaises(F.FidelityError): F.FidelityRecord(self.altered(lambda d: change(d['projection'][0])))

    def test_bounded_decompression_rejects_bomb(self):
        d = self.full.convert('REDUCED').document()
        d['payload'] = base64.b64encode(zlib.compress(b'x' * (F.MAX_RAW + 1))).decode()
        with self.assertRaises(F.FidelityError): F.FidelityRecord(F.canonical(d))

    def test_compressed_trailing_or_truncated_stream(self):
        d = self.full.convert('REDUCED').document(); good = base64.b64decode(d['payload'])
        for raw in (good + zlib.compress(b'extra'), good[:-1], b'bad'):
            d['payload'] = base64.b64encode(raw).decode()
            with self.assertRaises(F.FidelityError): F.FidelityRecord(F.canonical(d))

    def test_invalid_base64_and_payload_hash(self):
        d = self.full.convert('REDUCED').document()
        for encoded in ('!!!', base64.b64encode(zlib.compress(b'wrong source')).decode()):
            d['payload'] = encoded
            with self.assertRaises(F.FidelityError): F.FidelityRecord(F.canonical(d))

    def test_aggregation_order_independence(self):
        values = [record('part.' + str(i)).convert('PATCH') for i in range(4)]
        self.assertEqual(F.aggregate(values), F.aggregate(reversed(values)))
        result = json.loads(F.aggregate(values))
        self.assertEqual(result['totals']['counts']['living'], 12)
        self.assertFalse(result['historical_reconstruction'])

    def test_duplicate_partition_and_other_epoch_rejected(self):
        for other in (self.full, record(revision=1), record(epoch=2)):
            with self.assertRaisesRegex(F.FidelityError, 'DUPLICATE_PARTITION'):
                F.aggregate([self.full.convert('PATCH'), other.convert('AGGREGATE')])

    def test_aggregation_bounded_and_empty_rejected(self):
        with self.assertRaises(F.FidelityError): F.aggregate([])
        with self.assertRaises(F.FidelityError): F.aggregate([{}])
        with self.assertRaisesRegex(F.FidelityError, 'AGGREGATION_BUDGET'):
            F.aggregate(record('p.' + str(i)).convert('AGGREGATE') for i in range(F.MAX_MEMBERS + 1))

    def test_bounded_synthetic_representation_scale(self):
        rows = [record('bench.' + str(i)).convert('AGGREGATE') for i in range(64)]
        batch = json.loads(F.aggregate(rows))
        self.assertEqual(len(batch['sources']), 64)
        self.assertEqual(batch['totals']['counts']['living'], 192)
        self.assertLess(sum(len(r.data) for r in rows), len(self.full.data) * 64)

    def test_global_account_overflow_rejected(self):
        d = self.full.convert('AGGREGATE').document()
        for a in ('initial', 'current'): d['projection']['accounts'][a]['material_mg'] = F.MAX_INT - 30
        d['projection']['accounts']['sinks']['material_mg'] = 0
        a = F.FidelityRecord(F.canonical(d))
        d['source']['entity_id'] = 'other.partition'; b = F.FidelityRecord(F.canonical(d))
        with self.assertRaisesRegex(F.FidelityError, 'INTEGER_RANGE'): F.aggregate([a,b])

    def test_dictionary_mutation_does_not_mutate_record(self):
        d = self.full.document(); d['source']['owner_id'] = 'bad'
        self.assertEqual(self.full.source()['owner_id'], 'node.a')
        with self.assertRaises(Exception): self.full.data = b'{}'

    def test_patch_identity_and_count_limits(self):
        for change in (lambda rows: rows.append(rows[0]), lambda rows: rows.reverse(), lambda rows: rows[0].__setitem__('id','bad')):
            with self.assertRaises(F.FidelityError): F.FidelityRecord(self.altered(lambda d: change(d['projection'])))

    def test_packet_input_byte_and_depth_limits(self):
        self.assertEqual(F.MAX_PACKET, 2097152)  # Canonical A8 durable byte limit.
        # Valid source bytes can still become an oversized FULL envelope due to escaping.
        source_doc = json.loads(self.raw)
        source_doc['cut']['ecology_payload'] = '"' * 600000
        raw = F.canonical(source_doc)
        self.assertLess(len(raw), F.MAX_RAW)
        admission = self.admit(self.raw, F.digest(self.raw), self.origin)
        admission['source'] = F.binding(raw, F.digest(raw), self.origin)
        with self.assertRaisesRegex(F.FidelityError, 'BYTE_BUDGET'):
            F.FidelityRecord.from_snapshot(raw, F.digest(raw), self.origin, lambda *_: admission)
        for raw in (b'', b'x' * (F.MAX_PACKET + 1), b'[' * 1100 + b'0' + b']' * 1100):
            with self.assertRaises(F.FidelityError): F.FidelityRecord(raw)


if __name__ == '__main__':
    unittest.main()
