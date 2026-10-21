import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import random
import shutil
import signal
import subprocess
import sys
import time
import tempfile


def stop_processes(session, registry):
    groups = {session}
    if registry.exists():
        groups.update(int(pid) for pid in registry.read_text().split() if pid.isdecimal())
    for group in groups:
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            pass


def execute(lua, root, script, case, timeout):
    command = [lua, str(script.relative_to(root)), ".", "--case", case]
    with tempfile.TemporaryDirectory(prefix="annas-test-") as temporary:
        registry = Path(temporary) / "processes"
        env = dict(os.environ, ANNAS_TEST_PROCESS_LOG=str(registry), ANNAS_TEST_TMPDIR=temporary)
        process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True, env=env)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            stop_processes(process.pid, registry)
            stdout, stderr = process.communicate()
            return False, f"FAIL {case}\nTest exceeded {timeout:g} seconds\n{stdout}{stderr}"
        finally:
            stop_processes(process.pid, registry)
    expected = "PASS " + case
    passed = process.returncode == 0 and expected in stdout.splitlines()
    return passed, expected if passed else f"FAIL {case}\n{stdout}{stderr}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua", default="luajit")
    parser.add_argument("--suite", choices=("all", "async", "covers"), default="all")
    parser.add_argument("--case")
    parser.add_argument("--order", choices=("forward", "reverse", "shuffle"), default="forward")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=10)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.jobs < 1 or args.timeout <= 0:
        parser.error("jobs and timeout must be positive")
    lua = shutil.which(args.lua)
    if not lua:
        parser.error(f"LuaJIT not found: {args.lua}")
    root = Path(__file__).resolve().parent.parent
    scripts = sorted((root / "tests").glob("test_*.lua"))
    if args.suite == "async":
        scripts = [p for p in scripts if p.name == "test_async.lua"]
    elif args.suite == "covers":
        scripts = [p for p in scripts if p.name != "test_async.lua"]
    cases = []
    for script in scripts:
        result = subprocess.run([lua, str(script.relative_to(root)), ".", "--list"],
                                cwd=root, capture_output=True, text=True, timeout=args.timeout)
        if result.returncode:
            sys.stderr.write(result.stdout + result.stderr)
            return 1
        cases.extend((script, line[5:]) for line in result.stdout.splitlines() if line.startswith("TEST\t"))
    if args.case:
        cases = [(script, name) for script, name in cases if args.case in name]
    if not cases:
        parser.error("no matching tests")
    if len({name for _, name in cases}) != len(cases):
        parser.error("test names must be unique")
    if args.order == "reverse":
        cases.reverse()
    elif args.order == "shuffle":
        random.Random(args.seed).shuffle(cases)
    if args.list:
        for script, name in cases:
            print(f"{script.name}: {name}")
        return 0
    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda item: execute(lua, root, *item, args.timeout), cases))
    for _, message in results:
        print(message)
    passed = sum(ok for ok, _ in results)
    print(f"{passed}/{len(results)} tests passed in {time.monotonic() - started:.2f}s")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
