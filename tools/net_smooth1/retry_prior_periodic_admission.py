"""Test-only bounded retry for P1A periodic-writer admission backpressure.

A rejected ITEM is NOT durable success. Re-send the exact same operation_id and
payload only after the explicit transient P1A_WAIT_PRIOR_PERIODIC error.
Never retry unknown failures or fake an ACK. This is an orchestrator diagnostic,
not a gameplay/server semantics change.
"""
from __future__ import annotations
import time
from typing import Callable, Any

TRANSIENT_CODE = "P1A_WAIT_PRIOR_PERIODIC"

def retry_prior_periodic(
    send: Callable[[], dict[str, Any]],
    operation_id: str,
    budget_s: float = 30.0,
    now: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> tuple[dict[str, Any], dict[str, Any]]:
    if not operation_id or budget_s <= 0:
        raise ValueError("RETRY_PRIOR_PERIODIC_INVALID_REQUEST")
    started = now()
    attempts = 0
    backpressure = 0
    while True:
        attempts += 1
        transient = False
        try:
            response = send()
        except (OSError, RuntimeError, ValueError, KeyError) as exc:
            if TRANSIENT_CODE not in str(exc):
                raise
            transient = True
            response = {}
        else:
            result = response.get("item_command", {})
            if not isinstance(result, dict):
                raise RuntimeError("RETRY_PRIOR_PERIODIC_BAD_RESPONSE")
            transient = (
                result.get("success") is False and
                result.get("error_code") == TRANSIENT_CODE
            )
            if not transient:
                return response, {
                    "operation_id": operation_id,
                    "attempts": attempts,
                    "prior_periodic_rejections": backpressure,
                    "wait_ms": round((now() - started) * 1000, 3),
                }
        backpressure += 1
        elapsed = now() - started
        if elapsed >= budget_s:
            raise RuntimeError(
                f"R3_SLOW_ITEM_PRIOR_PERIODIC_BUDGET_EXHAUSTED: "
                f"operation_id={operation_id} attempts={attempts} "
                f"rejections={backpressure}"
            )
        sleep(min(0.3 + backpressure * 0.15, 1.2, budget_s - elapsed))
