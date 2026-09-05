"""Entry point: ``python tools/world_packs/wp_cli/__main__.py`` (or -m)."""
from __future__ import annotations

import sys

if __package__ in (None, ""):  # direct script invocation: bootstrap the package
    from pathlib import Path
    _PACKAGES_DIR = str(Path(__file__).resolve().parents[1])  # tools/world_packs
    if _PACKAGES_DIR not in sys.path:
        sys.path.insert(0, _PACKAGES_DIR)
    __package__ = "wp_cli"

from . import CLI_NAME, CLI_VERSION


def build_parser() -> argparse.ArgumentParser:
    import argparse

    from . import app

    parser = argparse.ArgumentParser(
        prog=CLI_NAME,
        description="WORLD PACKS authoring CLI: validate/resolve/doctor/inspect/index "
                    "over the existing WP1.0 library contract (no second resolver).")
    parser.add_argument("--version", action="version",
                        version=f"{CLI_NAME} {CLI_VERSION} (contract: WP1.0 library_contract.py)")
    sub = parser.add_subparsers(dest="command", metavar="COMMAND")

    p_validate = sub.add_parser(
        "validate", help="validate catalog + source locations against the WP1.0 contract")
    p_validate.add_argument("--catalog", type=str, default=None,
                            help="catalog JSON path (default: repo config/world_packs/library/catalog.v1.json)")
    p_validate.add_argument("--locations", type=str, default=None,
                            help="source locations JSON path (default: repo source_locations.v1.json)")
    p_validate.add_argument("--schema", type=str, default=None,
                            help="library schema path (default: repo library_schema.v1.json)")
    p_validate.set_defaults(handler=app.cmd_validate)

    from . import contract
    p_resolve = sub.add_parser(
        "resolve", help="compose and print the WP1.0 presentation lock for one recipe")
    p_resolve.add_argument("--recipe", type=str, default=contract.DEFAULT_RECIPE,
                           help=f"recipe id@version (default: {contract.DEFAULT_RECIPE})")
    for dest in ("catalog", "locations", "schema"):
        p_resolve.add_argument(f"--{dest}", type=str, default=None,
                               help=f"{dest} JSON path (default: repo document)")
    p_resolve.set_defaults(handler=app.cmd_resolve)

    p_doctor = sub.add_parser(
        "doctor", help="diagnose the authoring environment and WP1.0 contract state")
    for dest in ("catalog", "locations", "schema"):
        p_doctor.add_argument(f"--{dest}", type=str, default=None,
                              help=f"{dest} JSON path (default: repo document)")
    p_doctor.add_argument("--packs-dir", type=str, default=None,
                          help="legacy pack manifest directory (default: repo config/world_packs/packs)")
    p_doctor.add_argument("--skip-fixtures", action="store_true",
                          help="skip local fixture payload byte verification")
    p_doctor.add_argument("--json", action="store_true", help="machine-readable JSON report")
    p_doctor.set_defaults(handler=app.cmd_doctor)

    return parser


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "handler", None) is None:
        parser.print_help(sys.stderr)
        return 2
    try:
        return args.handler(args)
    except KeyboardInterrupt:  # pragma: no cover - interactive only
        print(f"{app.FAILURE_PREFIX} interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
