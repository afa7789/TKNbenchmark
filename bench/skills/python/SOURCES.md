# Sources

- https://docs.python.org/3.15/whatsnew/3.15.html — 3.15 features (lazy imports, frozendict, sentinel, comprehension unpacking, UTF-8 default, profiling package, re.prefixmatch, TaskGroup.cancel, typing PEPs 728/747/800), removals and new deprecations.
- https://docs.python.org/3.14/whatsnew/3.14.html — deferred annotations/annotationlib, t-strings, unparenthesized except, finally-control-flow warning, pathlib copy/move, compression.zstd, InterpreterPoolExecutor, forkserver default, asyncio policy and iscoroutinefunction deprecations.
- https://docs.python.org/3.13/whatsnew/3.13.html — PEP 594 dead-battery removals, copy.replace, warnings.deprecated, TypeIs, ReadOnly, TypeVar defaults, free-threading.
- https://peps.python.org/pep-0008/ — official style guide: naming, imports order, `is None`, no bare except, startswith/endswith.
- https://packaging.python.org/en/latest/guides/writing-pyproject-toml/ — pyproject.toml structure, SPDX `license` string + `license-files`, dependency-groups, scripts.
- https://docs.astral.sh/uv/guides/projects/ — uv init/add/run/lock/sync/build commands and generated project layout (uv_build backend).
- https://docs.astral.sh/uv/guides/package/ — uv build --no-sources, uv version --bump, uv publish, smoke-testing with `uv run --with --no-project`.
- https://docs.astral.sh/uv/concepts/projects/dependencies/ — `uv add --dev`/`--group`/`--optional` and the `[dependency-groups]` table.
- https://gist.github.com/minimaxir/c274d7cc12f683d93df2b1cc5bab853c — published Python agent rules: uv, ruff, mypy, pytest, type hints, no bare except, logging over print.
- https://pydevtools.com/handbook/how-to/how-to-write-agents-md-for-a-python-project/ — AGENTS.md consensus: src/tests layout, `uv run` for every tool, uv.lock generated, ruff check/format + type check + pytest.
- https://pydevtools.com/handbook/how-to/how-to-use-the-pydevtools-claude-md-template/ — why bare `python`/`pytest` escapes the project venv; use `uv run`.
- https://raw.githubusercontent.com/Taiizor/agents-md-cookbook/790e0ba0d9c7fc9b96992bd68f08e9bfcb4c217e/templates/python/AGENTS.md — AGENTS.md template with ruff + mypy + pytest pre-push gate.
- https://trav55555.github.io/ai-coding-primer/templates/cursorrules-python — Cursor rules consensus: uv, ruff, mypy, `X | None` over `Optional`.

Verified locally against the installed toolchain: Python 3.15.2 (Homebrew, macOS arm64), uv 0.10.12, ruff 0.17.6, mypy 2.4.1, pytest 9.2.0 — every API, error message, CLI flag and config snippet in SKILL.md was executed in a scratch project (since deleted).
