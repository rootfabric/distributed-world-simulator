#!/usr/bin/env python3
"""Validate native Item Graph snapshots, not just projected receipt totals."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path


def checks(data: dict, head: str, tree: str) -> dict[str, bool]:
    result = {}
    try:
        result['exact_subject'] = data['subject_head'] == head and data['subject_tree'] == tree
        result['focused_execution_pass'] = data['passed'] is True and data['failures'] == [] and data['assertions'] >= 270
        cases = data['cases']
        result['four_failure_window_cases'] = len(cases) == 4 and {(c['mode'], c['actor']) for c in cases} == {('normal', 'a'), ('before_apply', 'a'), ('after_apply', 'a'), ('actor_b', 'b')}
        for c in cases:
            mode, actor, receipt = c['mode'], c['actor'], c['receipt']
            before, window, after = c['initial_graph'], c['failure_window_graph'], c['final_graph']
            prefix = mode + ':'
            old = {i['item_id']: i for i in before['items']}
            new = {i['item_id']: i for i in after['items']}
            item_id = receipt['output_item_id']
            result[prefix + 'one_native_item_added'] = len(old) == len(before['items']) and len(new) == len(after['items']) and set(new) - set(old) == {item_id} and set(old) <= set(new)
            result[prefix + 'previous_native_items_unchanged'] = all(new.get(k) == v for k, v in old.items())
            item = new[item_id]
            quantity = item['quantity']
            result[prefix + 'native_quantity_and_owner'] = not isinstance(quantity, bool) and isinstance(quantity, (int, float)) and math.isfinite(quantity) and quantity == int(quantity) and quantity > 0 and quantity == receipt['output_quantity'] and item['definition_id'] == receipt['output_definition_id'] == 'item/ore' and item['location']['kind'] == 'INVENTORY' and item['location']['player_id'] == actor
            result[prefix + 'native_inventory_membership'] = after['inventories'][actor]['inventory'].count(item_id) == 1 and all(item_id not in inv['inventory'] for player, inv in after['inventories'].items() if player != actor)
            result[prefix + 'one_native_revision_and_tick'] = after['revision'] == before['revision'] + 1 and after['tick'] == before['tick'] + 1 and after['authority_owner_id'] == before['authority_owner_id'] == 'authority/a' and after['authority_epoch'] == before['authority_epoch'] == 1
            result[prefix + 'actual_failure_window'] = window == (before if mode == 'before_apply' else after)
            projected = c['material_view']['details']
            projected_items = [{'item_id': i['item_id'], 'definition_id': i['definition_id'], 'quantity': i['quantity'], 'player_id': i['location']['player_id'], 'slot_index': i['location']['slot_index']} for i in after['items'] if i['definition_id'] == 'item/ore' and i['location']['kind'] == 'INVENTORY' and i['location']['player_id'] in ('a', 'b')]
            result[prefix + 'projection_matches_native_items'] = projected['items'] == projected_items and all(projected['totals'][a] == sum(i['quantity'] for i in projected_items if i['player_id'] == a) for a in ('a', 'b'))
            result[prefix + 'projection_matches_native_version'] = projected['item_graph_revision'] == after['revision'] and projected['item_graph_tick'] == after['tick'] and projected['item_graph_checksum'] == after['checksum']
            mass = receipt['total_mass_kg']
            result[prefix + 'native_quantity_conserves_mass'] = math.isfinite(mass) and math.floor(mass) == quantity and receipt['represented_mass_kg'] == quantity and 0 <= receipt['residual_mass_kg'] < 1 and abs(mass - quantity - receipt['residual_mass_kg']) <= 1e-9
            result[prefix + 'correct_delivery_recovery'] = receipt['matter_replay'] == (mode in ('before_apply', 'after_apply')) and receipt['item_graph_replay'] == (mode == 'after_apply') and receipt['output_created_this_call'] == (mode != 'after_apply')
            stable = ('output_item_id', 'output_operation_id', 'output_quantity', 'batch_id', 'batch_checksum', 'source_id', 'source_operation_id', 'total_mass_kg', 'represented_mass_kg', 'residual_mass_kg')
            result[prefix + 'three_exact_retries'] = len(c['retries']) == 3 and all(all(r[k] == receipt[k] for k in stable) and r['item_graph_replay'] is True and r['matter_replay'] is True and r['output_created_this_call'] is False and r['current_item_graph_revision'] == after['revision'] and r['current_item_graph_tick'] == after['tick'] for r in c['retries'])
    except (KeyError, TypeError, ValueError, IndexError, OverflowError):
        result['well_formed_native_accounting'] = False
    return result


def validate(data: dict, head: str, tree: str) -> dict:
    positive = checks(data, head, tree)
    def output(c):
        return next(i for i in c['final_graph']['items'] if i['item_id'] == c['receipt']['output_item_id'])
    mutations = {
        'wrong_native_quantity': lambda d: output(d['cases'][0]).update(quantity=1),
        'duplicate_native_item': lambda d: d['cases'][0]['final_graph']['items'].append(copy.deepcopy(output(d['cases'][0]))),
        'wrong_native_inventory': lambda d: d['cases'][0]['final_graph']['inventories']['a'].update(inventory=[]),
        'wrong_native_owner': lambda d: output(d['cases'][0])['location'].update(player_id='b'),
        'pre_apply_already_mutated': lambda d: d['cases'][1].update(failure_window_graph=copy.deepcopy(d['cases'][1]['final_graph'])),
        'ack_lost_before_apply': lambda d: d['cases'][2].update(failure_window_graph=copy.deepcopy(d['cases'][2]['initial_graph'])),
        'projection_inflated': lambda d: d['cases'][0]['material_view']['details']['totals'].update(a=-1),
        'old_world_ore_corrupted': lambda d: d['cases'][0]['initial_graph']['items'][-1].update(quantity=-1),
        'retry_claims_new_output': lambda d: d['cases'][0]['retries'][0].update(output_created_this_call=True),
        'stale_subject': lambda d: d.update(subject_head='0' * 40),
    }
    rejected = []
    if all(positive.values()):
        for name, mutation in mutations.items():
            changed = copy.deepcopy(data)
            mutation(changed)
            if all(checks(changed, head, tree).values()):
                raise ValueError('MVP5_NATIVE_ACCOUNTING_FALSE_POSITIVE:' + name)
            rejected.append(name)
    return {'schema': 'distributed_world_simulator.mvp5_native_accounting_validation.v1', 'subject_head': head, 'subject_tree': tree, 'passed': all(positive.values()) and len(rejected) == len(mutations), 'checks': positive, 'negative_controls': rejected, 'independent_verdict': False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--head', required=True)
    parser.add_argument('--tree', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = validate(json.loads(args.evidence.read_text()), args.head, args.tree)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'passed': result['passed'], 'checks': len(result['checks']), 'negative_controls': result['negative_controls'], 'failed_checks': [k for k, v in result['checks'].items() if not v]}))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
