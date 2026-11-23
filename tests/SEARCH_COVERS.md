# Cover tests

Run from the plugin directory with Python 3 and LuaJIT 2.1 on PATH, on macOS or Linux:

```sh
python3 tests/run.py
```

The 27 tests cover HTML parsing, exact-file metadata, cache reuse, invalid and oversized responses, background loading, two-worker concurrency, per-cover timeouts, progress reporting, page changes and closing the menu. Each test runs in its own process with a fresh temporary cache. They use real OS processes, a fake HTTP transport and a headless UI scheduler. Workers synchronize through pipes. Run with `--order shuffle --seed 42 --jobs 2` to check a different order and concurrent execution.

`upstream/subprocess.lua` contains the POSIX subprocess functions from koreader-base `ffi/util.lua` at commit `ab0d8e2a2cfbbd3b57f7975077b0b124eac8dcd2`, with minimal FFI declarations for macOS and Linux. It is used by tests only; the plugin uses KOReader's installed module.

These tests do not check device rendering or live mirrors.
