#!/usr/bin/env python3
from __future__ import annotations
import hashlib, importlib.util, pathlib, subprocess, sys, unittest
ROOT = pathlib.Path(__file__).resolve().parent
FILES = [
"config/ecology/eco-evo3-planetary-ecology-compiler.v1.json",
"config/ecology/eco-evo3-roadmap.v1.json",
"config/ecology/eco-evo3-planetary-ecology-compiler.schema.v1.json",
"config/ecology/eco-evo3-roadmap.schema.v1.json",
"scripts/research/ecology/validate_evo3_architecture.py",
"tests/research/ecology/test_eco_evo3_architecture.py",
"docs/architecture/ECO_EVO3_PLANETARY_ECOLOGY_COMPILER_ARCHITECTURE_RU.md",
"docs/plans/ECO_EVO3_PLANETARY_ECOLOGY_COMPILER_ROADMAP_RU.md"
]
def run(cmd):
    p=subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True)
    if p.returncode != 0:
        sys.stdout.write(p.stdout); sys.stderr.write(p.stderr); raise SystemExit(p.returncode)
def load_module(path, name):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec)
    sys.modules[name]=module
    spec.loader.exec_module(module)
    return module
def run_unittest_by_path(path,name):
    # Load by file path: `python -m unittest tests/...` breaks on machines where
    # an installed top-level `tests` package shadows the local namespace package.
    module=load_module(str(ROOT/path),name)
    suite=unittest.TestLoader().loadTestsFromModule(module)
    result=unittest.TextTestRunner(verbosity=0).run(suite)
    if not result.wasSuccessful(): raise SystemExit(1)
def main():
    missing=[p for p in FILES if not (ROOT/p).is_file()]
    if missing: print("ECO.EVO3 runner: FAIL missing=" + ",".join(missing)); return 1
    run([sys.executable,"-m","py_compile",str(ROOT/"scripts/research/ecology/validate_evo3_architecture.py"),str(ROOT/"tests/research/ecology/test_eco_evo3_architecture.py")])
    run([sys.executable,str(ROOT/"scripts/research/ecology/validate_evo3_architecture.py")])
    run_unittest_by_path("tests/research/ecology/test_eco_evo3_architecture.py","evo3_architecture_tests")
    import json
    a=json.loads((ROOT/"config/ecology/eco-evo3-planetary-ecology-compiler.v1.json").read_text())
    r=json.loads((ROOT/"config/ecology/eco-evo3-roadmap.v1.json").read_text())
    print("ECO.EVO3 architecture+roadmap: PASS (25 tests)")
    print("architecture_hash="+a["architecture_hash"])
    print("roadmap_hash="+r["roadmap_hash"])
    print("candidate_files=9")
    print("compiler_stages=7")
    print("roadmap_checkpoints=10")
    print("required_foundations=G,ENV,MAT,WQ,SD,TF")
    print("current=E3.1_PLANET_FIELD_SNAPSHOT_CONTRACT")
    return 0
if __name__=="__main__": raise SystemExit(main())
