---
name: python
description: "Version-correct, idiomatic Python for the installed toolchain (Python 3.15.2): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Python code."
---

# Python 3.15 — writing correct, modern code

Target: CPython **3.15**. Check `requires-python` first. If older versions are supported, avoid the 3.14/3.15 features below or guard with `sys.version_info`.

## Toolchain (uv + ruff + pytest + mypy)
Homebrew/system Python is PEP 668 "externally-managed", so `pip install` fails. Always use uv:
```sh
uv init --package myapp       # src/myapp/__init__.py, [project.scripts], uv_build backend
uv init --lib mylib           # library: adds src/mylib/py.typed
uv add httpx                  # never hand-edit deps; uv.lock is generated
uv add --dev pytest ruff mypy # -> [dependency-groups] dev = [...]
uv run pytest -q              # run tools via `uv run`, not bare python/pytest
uv run ruff check --fix . && uv run ruff format . && uv run mypy src tests
uv sync --locked              # CI: fail if uv.lock is stale (uv lock --check also works)
uv version --bump minor; uv build --no-sources; uv publish   # dist/*.whl + sdist
uv run --with pkg --no-project -- python -c "import pkg"     # smoke-test the release
```
Scripts: PEP 723 header. Run with `uv run --script s.py`, add deps with `uv add --script s.py rich`:
```python
# /// script
# requires-python = ">=3.15"
# dependencies = ["httpx"]
# ///
```
`pyproject.toml` essentials (pytest ≥9 reads `[tool.pytest]` natively):
```toml
[project]
requires-python = ">=3.15"
license = "MIT"                       # SPDX string, not a table
[tool.ruff]
line-length = 88
target-version = "py315"
[tool.ruff.lint]
select = ["E", "F", "W", "I", "B", "UP", "SIM", "RUF"]
[tool.mypy]
strict = true
[tool.pytest]
testpaths = ["tests"]
addopts = ["-ra", "--strict-markers"]
```
Layout: `src/<pkg>/` and `tests/test_*.py`. Tests import the installed package; no `sys.path` hacks.

## New in 3.15
```python
lazy import json                    # PEP 810: module scope only
lazy from pathlib import Path       # loaded on first attribute use
```
- `lazy` is a SyntaxError inside a function, a class, or `try`/`except`. A missing module raises `ModuleNotFoundError` at **first use**, not at the import line. Use it to cut CLI startup time. For code that must also run on <3.15, `__lazy_modules__ = ["json"]` at module top makes plain imports lazy (older versions ignore it). Global switch: `-X lazy_imports=all|normal`.
- `frozendict(a=1)` is a builtin: immutable, hashable, a `Mapping` but **not** a `dict` subclass, and `fd | {...}` returns a frozendict. Use it for constant tables, `functools.cache` args, and safe defaults (`opts: frozendict[str, int] = frozendict()`). `json.dumps` and `pickle` accept it.
- Sentinels (PEP 661): `MISSING = sentinel("MISSING")`. The repr is `MISSING`, it stays identical across copy/pickle, and annotations can say `def f(x: int | MISSING = MISSING)`. Prefer this to `object()`.
- Unpacking in comprehensions: `[*xs for xs in lists]`, `{**d for d in dicts}`.
- **UTF-8 is now the default** for `open()`, `read_text()` and the rest. Use `encoding="locale"` for the old behaviour. Still pass `encoding="utf-8"` explicitly if older versions are supported.
- `re.prefixmatch()` is the new spelling of `re.match()`, which is soft-deprecated but not removed. `fullmatch`/`search` are unchanged.
- `asyncio.TaskGroup.cancel()` stops all tasks in the group cleanly.
- `bytearray.take_bytes(n)` takes bytes off the front without copying.
- New `math.integer` module (`gcd`, `isqrt`, `comb`...), `json.loads(s, array_hook=tuple)`, `tomllib` parses TOML 1.1.
- Typing: `TypedDict(..., closed=True)` / `extra_items=T` (PEP 728), `typing.TypeForm[T]` (PEP 747), `@typing.disjoint_base`.
- Profiling: `python -m profiling.sampling run --flamegraph -o out.html app.py` (also `attach PID`, `--live`, `--mode cpu`, `-a`). Deterministic: `python -m profiling.tracing` (`cProfile` is an alias); `profile` is deprecated.

## From 3.14 (still easy to get wrong)
- **Annotations are lazy** (PEP 649), so forward references need no quotes and no `from __future__ import annotations`, which is now legacy. Introspect with `annotationlib.get_annotations(obj, format=Format.FORWARDREF)` or `typing.get_type_hints`. Reading `__annotations__` directly can raise `NameError`.
- `except TimeoutError, ConnectionError:` is valid without parentheses, but only when there is no `as`.
- `return`/`break`/`continue` in `finally` is a SyntaxWarning.
- `t"Hi {name}"` is a `string.templatelib.Template` (`.strings`, `.interpolations`, `.values`), not a `str`.
- `pathlib.Path.copy(dst)`, `.copy_into(dir)`, `.move(dst)`, `.move_into(dir)`, `.info`.
- `compression.zstd` (`compress`/`decompress`). `functools.Placeholder` for `partial`. `heapq.heappush_max`/`heappop_max`/`heapify_max`.
- `concurrent.futures.InterpreterPoolExecutor`: parallelism without processes.
- The default multiprocessing start method is `forkserver` on Linux and `spawn` on macOS. Put process entry points under `if __name__ == "__main__":` and pass only picklable arguments.
- `bool(NotImplemented)` raises TypeError.

## Removed / deprecated — use the replacement
| Wrong | Right |
|---|---|
| `asyncio.get_event_loop()` with no loop (RuntimeError) | `asyncio.run(main())`, or `asyncio.get_running_loop()` inside a coroutine |
| `asyncio.set_event_loop_policy`, `*EventLoopPolicy` (removed in 3.16) | `asyncio.run(main(), loop_factory=...)` / `asyncio.Runner` |
| `asyncio.iscoroutinefunction` | `inspect.iscoroutinefunction` |
| `datetime.utcnow()`, `utcfromtimestamp` | `datetime.now(UTC)` (`from datetime import UTC`) |
| `strptime("03-01", "%m-%d")` (ValueError in 3.15) | include a year directive |
| `typing.List/Dict/Optional/Union` | `list[int]`, `dict[str, X]`, `X \| None` |
| `TypeVar("T")` + `Generic[T]` | `class Box[T]:`, `def f[T](x: T) -> T`, `type Pair[T] = tuple[T, T]` |
| `NamedTuple("P", x=int)` (TypeError) | class syntax |
| `typing.ByteString` | `collections.abc.Buffer` or `bytes \| bytearray` |
| `hashlib.sha256(string=b)` | `hashlib.sha256(b)` |
| `PurePath.is_reserved()` | `os.path.isreserved()` (Windows only) |
| `importlib.resources.files(package=...)` | `files("pkg")` |
| `sre_*`, `glob.glob0/1`, `cgi`, `crypt`, `telnetlib`, `pipes`, `imghdr` | `re`, `glob.glob`, a web framework, `hashlib`, `subprocess`+`shlex.quote` |
| `module.__version__` on stdlib modules | `sys.version_info` |

## Idioms that are both correct and fast
- Data containers: `@dataclass(slots=True, frozen=True, kw_only=True)` and `field(default_factory=list)`. Update with `copy.replace(obj, x=1)` (dataclasses, namedtuples, datetimes).
- Typing: `Self`, `@override`, `Protocol`, `TypeIs`; `warnings.deprecated` for your own APIs.
- Concurrency: `async with asyncio.TaskGroup() as tg:` with `tg.create_task(...)` and `async with asyncio.timeout(5):`. Failures arrive as an `ExceptionGroup`, so catch with `except* ValueError as eg:`. Never call `asyncio.run` inside a running loop. Run blocking calls with `await asyncio.to_thread(fn)`.
- Iteration: `itertools.batched(it, n, strict=True)`, `pairwise`, `zip(a, b, strict=True)`. Use `"".join(parts)` instead of `+=` in loops, a `set`/`frozenset` for membership, `collections.deque` for queues, `bisect`/`heapq` for ordered data. Hoist `re.compile` to module level, use `functools.cache` for pure functions (hashable arguments only).
- `subprocess.run([...], check=True, capture_output=True, text=True)`: a list of args, never `shell=True` with user input.
- `tomllib.load(f)` needs a file opened in `"rb"` mode.
- Libraries log via `logging.getLogger(__name__)`, never `print`.
- Free-threaded builds exist (`sys._is_gil_enabled()`), so guard shared mutable state with `threading.Lock`.

## Errors → fixes
- `SyntaxError: lazy import not allowed inside functions` → move the import to module top or use a plain `import`.
- `error: externally-managed-environment` → `uv add`/`uv run` (or `python3 -m venv .venv`).
- `TypeError: unhashable type: 'dict'` (cache/set key) → `frozendict` or tuple.
- Surface deprecations early: `uv run pytest -W error::DeprecationWarning`.
