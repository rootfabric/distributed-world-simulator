#!/usr/bin/env python3
"""One-shot ACT0 reconstruction from pinned Git objects; never updates Git refs."""
from __future__ import annotations

import ast
import copy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

BASE = "3d7672cba293d8e7bd72427b803f73fc8fcee5da"
P7 = "V0_P7_BOUNDED_TERRAIN_MUTATION"
MVP = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"
BRANCH = "feature/v0-mvp-playable-seamless-planet-r1"
EPOCH = "E2026-09-09-V0-MVP-R1"
WO = "V0-MVP-R1-WO-001"
H = "config/control/harness/"
EX = H + "executions/" + EPOCH + "/"
ACT = H + "activation/V0-MVP-R1-ACTIVATION-001.v1.json"
DOC = "docs/control/mvp-act0-r1/"
PHASE = "MVP_ACTIVATED_IMPLEMENTATION_DISPATCHED"
ACCEPT = H + "acceptance/V0-P7-R1-CHECKPOINT-ACCEPTED-001.v1.json"
ADD2 = H + "acceptance/V0-P7-R1-CHECKPOINT-ACCEPTED-ADDENDUM-002.v1.json"
STAMP = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
ROOT = Path.cwd()
CHANGED: list[str] = []


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True, encoding="utf-8").strip()


def source(path: str) -> str:
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"]).decode("utf-8")


def original(path: str) -> dict:
    return json.loads(source(path))


def write(path: str, value: dict | str) -> None:
    destination = ROOT / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, ensure_ascii=False, indent=2) + "\n" if isinstance(value, dict) else value
    destination.write_text(text, encoding="utf-8")
    CHANGED.append(path)


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError("SOURCE_ANCHOR_NOT_UNIQUE:" + old[:100])
    return text.replace(old, new, 1)


def main() -> None:
    if git("rev-parse", "origin/main") != BASE:
        raise ValueError("CANONICAL_MAIN_MOVED_REVIEW_REQUIRED")
    if git("branch", "--show-current") != "control/v0-mvp-act0-r1":
        raise ValueError("ASSEMBLER_WRONG_BRANCH")
    if git("status", "--porcelain", "--untracked-files=no"):
        raise ValueError("ASSEMBLER_REQUIRES_CLEAN_TRACKED_CHECKOUT")
    if (ROOT / ACT).exists():
        raise ValueError("ACT0_ALREADY_ASSEMBLED_DO_NOT_REWRITE_EVENTS")
    prior = git("diff", "--name-only", BASE, "HEAD").splitlines()
    if any(not (p.startswith(DOC) or p == ".github/workflows/mvp-act0-assemble.yml") for p in prior):
        raise ValueError("PREASSEMBLY_SCOPE_DRIFT")
    acceptance = original(ACCEPT)
    addendum = original(ADD2)
    if acceptance.get("status") != "ACCEPTED":
        raise ValueError("P7_NOT_ACCEPTED")
    base_tree = git("rev-parse", BASE + "^{tree}")
    registry = original("config/control/project-program-registry.v1.json")
    scheduler = original(H + "scheduler-policy.v1.json")
    goals = original(H + "project-goals.v1.json")
    train = original(H + "v0-product-train-policy.v1.json")
    work_map = original(H + "v0-current-work-map.v1.json")
    catalog = original(H + "checkpoint-catalog.v1.json")
    generation = registry["registry_generation"] + 1
    if generation != 82 or scheduler["v0_product_train_routing"]["runtime_mutation_allowed_now"] is not False:
        raise ValueError("UNEXPECTED_BASE_LEASE_STATE")

    inherited = {"checkpoint": P7, "acceptance_record": ACCEPT, "latest_addendum": ADD2,
                 "exact_product_base": BASE, "exact_product_base_tree": base_tree,
                 "accepted_runtime_head": "5a1d79c6889136c40daf97f69feb90512c214009",
                 "accepted_runtime_tree": "00581408e4ba9033fde16b43915945e73e18fcb2"}
    common = {"current_checkpoint": MVP, "current_phase": PHASE}
    routing = scheduler["v0_product_train_routing"]
    routing.update(common)
    routing.update(runtime_mutation_allowed_now=True, next_runtime_checkpoint=MVP,
                   next_runtime_checkpoint_eligible=False, accepted_predecessor_checkpoint=P7,
                   accepted_predecessor_base=BASE, p7_acceptance=inherited,
                   control_next_actor="IMPLEMENTER", control_next_action="BEGIN_V0_MVP_PLAYABLE_SEAMLESS_PLANET_COMPOSITION",
                   control_resume_condition="Main-owned ACT0 plus exact post-merge epoch audit and Director dispatch; no gameplay worker has been launched by ACT0.")
    activation_identity = {"activation_record": ACT, "exact_execution_base": BASE,
                           "exact_execution_base_tree": base_tree, "project_epoch": EPOCH,
                           "work_order_id": WO, "runtime_branch": BRANCH, "control_generation": generation}
    routing["mvp_activation"] = activation_identity
    routing["p7_7"]["state"] = "MERGED_CANONICALLY_ACCEPTED"
    scheduler["parallel_product_checkpoints"]["checkpoints"] = [MVP]
    scheduler["parallel_product_checkpoints"]["future_checkpoints_not_yet_eligible"] = [
        p for p in scheduler["parallel_product_checkpoints"]["future_checkpoints_not_yet_eligible"] if p != MVP]
    lease = scheduler["pre_h0_3_runtime_mutation_lease"]
    lease.update(effective_registry_generation=generation, holder_checkpoint=MVP, holder_branch=BRANCH,
                 state="RESERVED_MVP_SINGLE_RUNTIME_WORKER", reason="ACT0 rotates the single slot after accepted P7; actual execution requires canonical adoption, current epoch audit and Director dispatch.")
    write(H + "scheduler-policy.v1.json", scheduler)

    train.update(common)
    train["branch_succession"]["naming"]["MVP"] = BRANCH
    for item in train["checkpoint_sequence"]:
        if item["id"] == P7:
            item.update(state="ACCEPTED", acceptance_record=ACCEPT, acceptance_addendum=ADD2)
            item["p7_7"]["state"] = "MERGED_CANONICALLY_ACCEPTED"
        if item["id"] == MVP:
            item.update(state="ACTIVATED_DISPATCHED", execution_base=BASE, execution_base_tree=base_tree,
                        project_epoch=EPOCH, work_order_id=WO, runtime_branch=BRANCH,
                        activation_record=ACT, risk_class="CRITICAL")
    train["current_p7_activation_route"].update(historical_only=True, superseded_by="current_mvp_activation_route",
        runtime_mutation="FROZEN_ACCEPTED", mutation_lease="RELEASED_TO_MVP", next="MVP_ACT0", p7_7="ACCEPTED")
    train["current_mvp_activation_route"] = dict(activation_identity, accepted_predecessor_checkpoint=P7,
        runtime_mutation="CONDITIONAL_ON_CANONICAL_ADOPTION_AND_EPOCH_AUDIT", director_dispatch="RECORDED_NOT_WORKER_LAUNCH")
    write(H + "v0-product-train-policy.v1.json", train)

    mvp = catalog["checkpoints"][MVP]
    mvp.update(activation_state="ACTIVATED_DISPATCHED", activation_record=ACT, project_epoch=EPOCH,
               work_order_id=WO, exact_execution_base=BASE)
    extra = ["FULL_WORLD_CORE_REGRESSION_PASS", "POST_BUILD_CRITIQUE_COMPLETED", "EVIDENCE_MAP_COMPLETE",
             "REVIEW_HEAD_EXACT_AND_FRESH", "TESTED_HEADS_EXACT_AND_FRESH", "CRITICAL_CROSS_BRANCH_OVERLAP_ZERO",
             "HUMAN_ATTENTION_QUEUE_EMPTY_OR_RESOLVED"]
    mvp["required_predicates"] = list(dict.fromkeys(mvp["required_predicates"] + extra))
    mvp["network_baseline"] = "SERVER_PREDICTED"
    write(H + "checkpoint-catalog.v1.json", catalog)
    outcomes = [p for p in mvp["required_predicates"] if p.startswith("MVP_")]
    work_map["historical_p7_execution_order"] = work_map["execution_order"]
    work_map.update(status=PHASE, authored_against_main=BASE, accepted_predecessor=P7,
        accepted_predecessor_product_lineage=BASE, accepted_predecessor_acceptance_record=ACCEPT,
        accepted_predecessor_acceptance_addendum=ADD2, current_campaign=MVP,
        current_human_plan=DOC + "ACT0_RU.md", primary_machine_plan=ACT, activation_record=ACT,
        project_epoch=EPOCH, work_order_id=WO, runtime_branch=BRANCH, execution_order=outcomes + ["MVP_REVIEW_VERIFICATION_PC0", "HUMAN_MVP_ACCEPTANCE"],
        exact_runtime_execution_base=BASE, exact_runtime_execution_base_tree=base_tree, control_main_base=BASE,
        next_action="BEGIN_V0_MVP_PLAYABLE_SEAMLESS_PLANET_COMPOSITION",
        sequencing_override="ACT0: current MVP controls supersede historical P7 substep prose; historical execution/acceptance remain immutable.")
    work_map["p7_7"]["state"] = "MERGED_CANONICALLY_ACCEPTED"
    work_map["mvp"] = activation_identity
    write(H + "v0-current-work-map.v1.json", work_map)
    for goal in goals["current_goal_graph"]:
        if goal["id"] == "V0_P7_PRODUCT":
            goal.update(current_phase="ACCEPTED", eligibility="ACCEPTED", status="ACCEPTED",
                        reason="P7 and its post-acceptance repair are canonical; immutable acceptance/addenda retained.")
        if goal["id"] == "V0_PLAYABLE_SEAMLESS_PLANET":
            goal.update(target_checkpoint=MVP, current_phase=PHASE, eligibility="ACTIVATED_DISPATCHED",
                        reason="ACT0 opens one bounded composition Work Order over the exact accepted P7 base; not MVP acceptance.")
        if goal["id"] == "V0_PRODUCT_TRAIN":
            goal["selection_rule"] = "MVP ACT0 is activated; current epoch and Director dispatch govern one implementation worker. Research is not an implicit blocker."
    goals["selection_rule"] = "MVP first: execute the main-owned ACT0 Work Order after epoch audit; no automatic research or P8 activation."
    write(H + "project-goals.v1.json", goals)

    program = registry["programs"]["V0"]
    program.update(branch=BRANCH, passport_path="config/control/branches/feature__v0-mvp-playable-seamless-planet-r1.v1.json",
        short_description="MVP: shared graphical world over accepted SM1 and P7.",
        current_stage="MVP ACT0 / bounded composition dispatch", stage_status=PHASE,
        progress_note="ACT0 declared; gameplay runtime has not started. Accepted P7 is preserved; use the fresh MVP epoch and Work Order.",
        last_accepted_checkpoint="V0_P7_BOUNDED_TERRAIN_MUTATION + post-acceptance ADDENDUM-002",
        next_stage="MVP1 shared graphical scene; canonical adoption and exact epoch audit required before mutation.",
        implementation_blockers=[], acceptance_blockers=list(mvp["required_predicates"]))
    program["product_execution_base"] = dict(branch="accepted P7 canonical main", sha=BASE,
        accepted_runtime_head=inherited["accepted_runtime_head"], accepted_runtime_tree=inherited["accepted_runtime_tree"],
        declares_checkpoint_acceptance=False, acceptance_record=ACCEPT, acceptance_addendum=ADD2,
        reason="Accepted P7 runtime plus its canonical control closure; does not declare MVP acceptance.")
    program["p7_7"]["state"] = "MERGED_CANONICALLY_ACCEPTED"
    program["mvp"] = activation_identity
    registry.update(registry_generation=generation, updated_at_utc=STAMP,
                    control_checkpoint="ACT0: accepted P7 -> one bounded MVP composition epoch and Work Order.")
    registry["programs"]["HARNESS"].update(
        progress_note="P7 canonical closure is complete; ACT0 changes current product routing, not the independent H0.2 pilot.",
        next_stage="Verify current MVP epoch/dispatch and keep one global runtime worker before H0.3.")
    lane = registry["coordination"]["lanes"]["MVP"]
    lane.update(current_checkpoint=MVP, phase=PHASE, next_actor="IMPLEMENTER",
        next_action="BEGIN_V0_MVP_PLAYABLE_SEAMLESS_PLANET_COMPOSITION",
        evidence_paths=[ACCEPT, ADD2, ACT], open_gaps=["All MVP product predicates remain unproven; ACT0 is activation only."])
    registry["coordination"]["observed_main"] = BASE
    registry["convergence_order"]["v0_train"] = [
        s.replace("P7 runtime MERGED; canonical closure reconciliation", "P7 ACCEPTED with post-acceptance correction")
        for s in registry["convergence_order"]["v0_train"]]
    registry["convergence_order"]["now_parallel"][0] = "V0 MVP composition after accepted P7; one runtime mutation slot"
    registry["global_blocked_transitions"] = [x for x in registry["global_blocked_transitions"]
        if x.get("stage") not in {"V0-P7 RUNTIME MUTATION START", "V0-P7 CHECKPOINT ACCEPTANCE"}]
    registry["global_blocked_transitions"].append({"stage":"MVP CHECKPOINT ACCEPTANCE", "blocked_by":"ALL_MVP_PRODUCT_PREDICATES_PLUS_FRESH_REVIEW_VERIFIER_AND_HUMAN_ACCEPTANCE"})
    write("config/control/project-program-registry.v1.json", registry)

    passport = original("config/control/branches/control__project-focus-harness-reconciliation-r1.v1.json")
    passport.pop("activation_passport_rotation", None)
    for key in ("branch", "program", "role", "short_description", "purpose", "expected_outcome", "current_stage",
                "stage_status", "progress_note", "last_accepted_checkpoint", "next_stage", "blockers", "health_declared"):
        passport[key] = program[key]
    passport.update(base_commit=BASE, parent_branch_or_checkpoint="Canonical P7 + ADDENDUM-002 @ " + BASE,
        dependencies=[P7, "SM1_ACCEPTED", "SERVER_PREDICTED"],
        owned_paths=["scripts/runtime/networked_gameplay/mvp/**", "scripts/app/**", "scenes/labs/mvp/**",
                     "tests/runtime/test_v0_mvp_*", "tests/integration/test_v0_mvp_*", "tests/fixtures/v0_mvp/**", "RUN_V0_MVP_*", EX + "**", DOC + "**"],
        runtime_paths=["scripts/runtime/networked_gameplay/mvp/**", "scripts/app/**", "scenes/labs/mvp/**"],
        validation_paths=["tests/runtime/test_v0_mvp_*", "tests/integration/test_v0_mvp_*", "RUN_V0_MVP_*"],
        tested_heads={"runtime":"NOT_STARTED", "focused":"NOT_STARTED", "full_regression":"NOT_STARTED"},
        baseline_evidence_note="P7 evidence is inherited capability evidence only. No MVP test, review or acceptance is claimed by ACT0.")
    write(program["passport_path"], passport)
    allowed = passport["owned_paths"]
    forbidden = ["config/architecture/**", "config/control/architecture-ownership.v1.json", H + "acceptance/**",
        "scripts/simulation/matter/**", "scripts/network/**", "scripts/runtime/networked_gameplay/m4/**",
        "scripts/runtime/networked_gameplay/sm1/**", "scripts/runtime/networked_gameplay/p7/**", "project.godot"]
    work_order = dict(schema="distributed_world_simulator.work_order.v1", work_order_id=WO,
        project_epoch=EPOCH, program="V0", goal_checkpoint=MVP, state="DISPATCHED", work_order_type="INTEGRATION",
        base_sha=BASE, branch=BRANCH, scope="MVP1–MVP8: интеграция уже принятых SM1/P7/Item/Construction/persistence в одну запускаемую двухклиентскую сцену. Никаких новых владельцев канонического состояния.",
        allowed_paths=allowed, forbidden_paths=forbidden, required_predicates=mvp["required_predicates"],
        required_outputs=outcomes + ["Exact-head Evidence Map and fresh independent roles"],
        stop_conditions=["New canonical owner or foundation change required", "Second active runtime worker", "Missing canonical ACT0 or stale epoch", "Attempt to self-accept or self-merge"],
        risk_class="CRITICAL", risk_reasons=["Composes mutable shared world, authority handoff and exactly-once recovery"],
        review_required=True, required_review_roles=["IMPLEMENTER","REVIEWER","VERIFIER","DIRECTOR","HUMAN"],
        repair_context_required=False, evidence_map_required=True, issued_at_utc=STAMP,
        human_approval_required_for=["RUNTIME_FEATURE_MERGE","MVP_CHECKPOINT_ACCEPTANCE"],
        notes="ACT0 records dispatch authority, not a running agent. Implementation starts only on canonical adoption plus current epoch audit. No product predicate is complete at activation.")
    work_order["design_brief"] = dict(problem_statement="Принятые компоненты ещё не доказаны как единый пользовательский сценарий.",
        current_behavior="SM1 и P7 приняты; MVP composition не выполнен.", desired_behavior="Два клиента видят один мир, копают, пересекают A→B→A и восстанавливают одинаковое каноническое состояние.",
        alternatives_considered=["New demo-only terrain/inventory", "Wait for unrelated research"],
        selected_design="Small composition adapters over existing owners", why_selected="No duplicate truth or new foundation",
        affected_owners=["V0","MATTER_MW4_MW10","SM1","ITEM_GRAPH","CONSTRUCTION","PERSISTENCE"],
        dependencies=[P7,"SM1_ACCEPTED","SERVER_PREDICTED"], non_goals=["ECO","FABRIC","WORLDGEN1_FULL","RF1","P8","WORLD_PACKS"],
        expected_risks=["Presentation/canonical divergence", "Duplicate output on replay", "Seam reconnect or respawn"],
        validation_plan=["Focused two-client scene", "A-B-A continuity", "Dig and exactly-once accounting", "Reconnect/restart", "Bounded interactive workload", "Full world/core", "Fresh Reviewer/Verifier and PC0"])
    write(EX + "work-orders/" + WO + ".v1.json", work_order)
    write(EX + "project-epoch.v1.json", dict(schema="distributed_world_simulator.project_epoch.v1",
        epoch_id=EPOCH, base_sha=BASE, registry_generation=generation,
        architecture_revision=registry["architecture_revision"], harness_revision=scheduler["harness_revision"],
        created_at_utc=STAMP, eligible_checkpoints=[MVP], status="ACTIVE", decision="CONTINUE"))
    transition = original(H + "executions/E2026-08-30-V0-P7-R1/transition-table.v1.json")
    write(EX + "transition-table.v1.json", transition)
    for seq, kind, state in [(1,"WORK_ORDER_CREATED","PLANNED"),(2,"DISPATCHED","DISPATCHED")]:
        name = "0001-work-order-created.v1.json" if seq == 1 else "0002-director-dispatched.v1.json"
        write(EX + "events/" + WO + "/" + name, dict(schema="distributed_world_simulator.harness_event.v1",
            event_id=EPOCH + "-%04d" % seq, project_epoch=EPOCH, work_order_id=WO, sequence=seq,
            event_type=kind, work_state=state, recorded_at_utc=STAMP, actor="DIRECTOR", branch=BRANCH,
            head_sha=BASE, predicate="MVP_WORK_ORDER_CREATED" if seq == 1 else "MVP_WORK_ORDER_AND_DIRECTOR_DISPATCH",
            command="ACT0_CONTROL_AUTHORIZATION_NOT_WORKER_EXECUTION", exit_code=0, evidence_paths=[ACT],
            summary="ACT0: создание bounded Work Order." if seq == 1 else "ACT0: разрешён один bounded MVP worker после main adoption и актуального epoch audit; worker ещё не запущен."))
    write(ACT, dict(schema="distributed_world_simulator.v0_mvp_activation.v1",
        activation_id="V0-MVP-R1-ACTIVATION-001", checkpoint=MVP, program="V0", state="DISPATCHED",
        recorded_at_utc=STAMP, main_declared_exact_successor_base=BASE, exact_successor_base_tree=base_tree,
        accepted_predecessor=inherited, **activation_identity,
        authorization=dict(owner_directive="отлично. реализуй ACT0 MVP activation / exact base / epoch / Work Order", scope="ACT0_ONLY_NOT_MVP_ACCEPTANCE", source="OWNER_CONVERSATION_DIRECTIVE"),
        mutation_lease=dict(capacity=1, holder_checkpoint=MVP, holder_branch=BRANCH, runtime_mutation_authorized=True,
            effective_only_after_main_adoption=True, post_merge_epoch_audit_required=True, actual_worker_started=False),
        director_dispatch=dict(status="DISPATCHED", actor="DIRECTOR", event=EX+"events/"+WO+"/0002-director-dispatched.v1.json"),
        base_control_observation=dict(routing_runtime_allowed=False, lease_state=original(H+"scheduler-policy.v1.json")["pre_h0_3_runtime_mutation_lease"]["state"],
            interpretation="No current canonical V0 mutation authorization at base; not a claim about all physical processes or other agents."),
        human_gate="RUNTIME_FEATURE_MERGE", checkpoint_acceptance_gate="HUMAN_MVP_ACCEPTANCE",
        successor_runtime_merge_authorized=False, mvp_accepted=False))

    planner = source("scripts/harness/checkpoint_planner.py")
    planner = replace_once(planner, '_PRODUCT_CHECKPOINTS = {', 'MVP = "' + MVP + '"\n_PRODUCT_CHECKPOINTS = {\n    MVP,')
    for dictionary, value in [("_PRODUCT_GATE_NAMES","v0_mvp_gate"),("_PRODUCT_BEGIN_ACTIONS","BEGIN_V0_MVP_PLAYABLE_SEAMLESS_PLANET_COMPOSITION"),
        ("_PRODUCT_VERIFY_ACTIONS","VERIFY_V0_MVP_EXACT_HEAD"),("_PRODUCT_DISPATCH_ACTIONS","DIRECTOR_DISPATCH_ACCEPTED_P7_BASE_V0_MVP_WORK_ORDER")]:
        planner = replace_once(planner, dictionary + " = {", dictionary + ' = {\n    MVP: "' + value + '",')
    planner = replace_once(planner, 'current == "V0_P7_BOUNDED_TERRAIN_MUTATION" else "HIGH"', 'current in {"V0_P7_BOUNDED_TERRAIN_MUTATION", MVP} else "HIGH"')
    anchor = '    return {\n        "mode": "PLANNING_ONLY" if not active'
    insert = '''    if current == MVP:
        routing = scheduler.get("v0_product_train_routing", {})
        declared = routing.get("mvp_activation", {})
        if (routing.get("current_checkpoint") != MVP
                or routing.get("accepted_predecessor_checkpoint") != "V0_P7_BOUNDED_TERRAIN_MUTATION"
                or not declared.get("exact_execution_base")
                or work_order.get("base_sha") != declared.get("exact_execution_base")
                or work_order.get("project_epoch") != declared.get("project_epoch")
                or work_order.get("work_order_id") != declared.get("work_order_id")
                or work_order.get("branch") != declared.get("runtime_branch")):
            raise ValueError("MVP_MAIN_DECLARED_ACTIVATION_MISMATCH")
        if mutating and routing.get("runtime_mutation_allowed_now") is not True:
            raise ValueError("MVP_RUNTIME_DISPATCH_NOT_AUTHORIZED")
        gate.update(accepted_predecessor_checkpoint="V0_P7_BOUNDED_TERRAIN_MUTATION",
                    accepted_predecessor_base=declared["exact_execution_base"],
                    composition_truth="EXISTING_SM1_P7_ITEM_CONSTRUCTION_PERSISTENCE",
                    director_dispatch_required=True, runtime_merge_human_gated=True,
                    checkpoint_acceptance_human_gated=True,
                    bounded_implementation_may_proceed_with_prior_acceptance_debt=False)

'''
    planner = replace_once(planner, anchor, insert + anchor)
    # Seam handoff is an accepted MVP dependency, not the old S1 prohibition.
    planner = replace_once(planner, '            "SERVER_HANDOFF",', '            "NEW_AUTHORITY_FOUNDATION" if current == MVP else "SERVER_HANDOFF",')
    ast.parse(planner)
    write("scripts/harness/checkpoint_planner.py", planner)

    overview = source("scripts/harness/project_overview.py")
    overview = replace_once(overview, '    if routing.get("current_phase") != HOLD:\n        return None', '''    if routing.get("current_phase") != HOLD:
        # Historical accepted P7 remains inspectable after the product lease rotates.
        if checkpoint == P7:
            acceptance = load_checkpoint_acceptance(root, P7, "main", canonical_head=head)
            if acceptance is not None:
                return {"authority": "CANONICAL_MAIN_SNAPSHOT", "canonical_ref": ref,
                        "canonical_head": head, "checkpoint": P7, "runtime_authorized": False,
                        "checkpoint_acceptance": acceptance, "mission_complete": True,
                        "mission_exit_allowed": True, "role_exit_allowed": False,
                        "next_actor": "DIRECTOR", "next_action": "FOLLOW_CURRENT_PRODUCT_CHECKPOINT",
                        "resume_condition": "Use the current main-owned product activation.",
                        "instruction": "Historical P7 acceptance never reactivates its runtime worker."}
        return None''')
    ast.parse(overview)
    write("scripts/harness/project_overview.py", overview)

    write(DOC + "ACT0_RU.md", f'''# ACT0 — активация MVP после принятого P7

Exact product base: `{BASE}`; tree `{base_tree}`.
Epoch: `{EPOCH}`; Work Order: `{WO}`; runtime branch: `{BRANCH}`.
Generation: `{generation}`; risk: CRITICAL; capacity: one runtime worker.

ACT0 не означает готовность MVP. Все product predicates остаются незавершёнными.
Branch-only candidate не даёт полномочий. До main adoption старый canonical route
должен возвращать Director и запрещать runtime; после merge необходимо выполнить
PC0 и записать exact epoch audit CONTINUE с реальным новым main SHA в свежем
execution ledger. Нельзя менять исторический epoch, подставлять будущий merge SHA
или выдавать запись DISPATCHED за запущенного агента.

Первое runtime-действие после разрешающего Drive — MVP_SHARED_GRAPHICAL_SCENE.
Затем: два клиента; A→B→A; каноническое копание обоим клиентам; exactly-once material;
Item/Construction/persistence; reconnect/restart; bounded interactive workload.
Полная world/core-регрессия, fresh Reviewer и Verifier, PC0 и Human MVP acceptance
обязательны. ECO/FABRIC/WORLDGEN1 full/RF1/P8/PACKS не являются preconditions.

Runtime branch должна содержать принятый ACT0 control commit. Она основывается на
exact accepted-P7 product base через control-only descendant, а не на голом старом
checkout без новой эпохи. Изменения runtime при ACT0 запрещены.

`assemble.py` — одноразовый воспроизводимый сборщик candidate из pinned Git blobs;
не authority и не scheduler. Он не выполняет push, merge, acceptance или worker launch.
''')
    fingerprints = {p: {"base_blob": git("rev-parse", f"{BASE}:{p}"),
                       "candidate_sha256": hashlib.sha256((ROOT/p).read_bytes()).hexdigest()}
                    for p in CHANGED if subprocess.run(["git","cat-file","-e",f"{BASE}:{p}"],capture_output=True).returncode == 0}
    write(DOC + "assembly-inputs.v1.json", dict(schema="distributed_world_simulator.act0_assembly_inputs.v1",
        base_head=BASE, base_tree=base_tree, recorded_at_utc=STAMP, files=fingerprints,
        runtime_modified=False, independent_verdict="NOT_ISSUED", activation_canonical=False))
    for path in CHANGED:
        if path.endswith(".json"):
            json.loads((ROOT/path).read_text(encoding="utf-8"))
    print(json.dumps({"assembled": True, "paths": CHANGED, "base": BASE}, ensure_ascii=False))


if __name__ == "__main__":
    main()
