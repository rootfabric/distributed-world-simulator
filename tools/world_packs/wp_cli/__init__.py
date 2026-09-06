"""WORLD PACKS authoring CLI (WP-TOOLS1).

A stdlib-first command surface around the existing WP1.0 metadata contract in
``tools/world_packs/library_contract.py``. This package NEVER re-implements
resolver semantics: validate/resolve/digest behaviour is imported from the
single existing contract module so there cannot be a second incompatible
resolver.
"""
from __future__ import annotations

CLI_NAME = "wp"
CLI_VERSION = "1.0.0"

__all__ = ["CLI_NAME", "CLI_VERSION"]
