---
name: neuro-san-coded-tool
description: Create coded tools (Python classes) for neuro-san agent networks. Use this skill when implementing a CodedTool class, wiring it into a HOCON file, handling args and sly_data, writing async or sync invoke methods, calling external APIs or databases, registering a tool in the toolbox, reporting progress, calling other agents from a tool, writing unit tests, or debugging class resolution issues.
when_to_use: When asked to create a coded tool, implement a Python tool for a neuro-san agent, add a class field to a HOCON agent definition, handle sly_data in Python, write tests for a coded tool, or troubleshoot import/class resolution errors in neuro-san.
argument-hint: [tool-name] [what-it-does]
allowed-tools: Read Bash
---

# Neuro-SAN Coded Tool Skill

Expert reference for writing Python `CodedTool` implementations.

**Tracks neuro-san `0.6.98` and neuro-san-studio `0.3.20`.**

---

## 1. WHAT IS A CODED TOOL?

A Python class implementing non-LLM logic inside an agent network — database queries, HTTP
calls, computations, file I/O, external API integrations. The framework calls
`async_invoke()` (preferred) or `invoke()` when an LLM agent decides to use the tool.

Coded tools are normally **leaf nodes**: an LLM agent calls them to do concrete work.

```
User → FrontMan
         └─→ Specialist (LLM agent)
                  └─→ MyCodedTool   ← your Python class
```

They do **not** participate in AAOSA. Never put `${aaosa_call}`, `${aaosa_instructions}`, or
`command` on a coded tool's HOCON entry, and never implement Determine/Fulfill logic in
Python — that is the LLM agents' job.

The one exception: a coded tool **can** call other agents using the `BranchActivation`
pattern. See `references/advanced.md`.

---

## 2. THE INTERFACE

```python
from typing import Any
from typing import Dict

from neuro_san.interfaces.coded_tool import CodedTool


class MyTool(CodedTool):

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Any:
        ...

    def invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Any:
        ...
```

Exactly two methods. The declared return type is `Any` — whatever you return goes into the
chat stream. Most studio tools narrow it to `Union[Dict[str, Any], str]` by convention.

**Override at least one.** The base `async_invoke()` raises `NotImplementedError`; the base
`invoke()` deliberately does nothing and returns `None` rather than raising, so a
missing-but-called `invoke()` fails silently.

| Scenario | Method |
|---|---|
| Any I/O — HTTP, DB, file, sleep | `async_invoke()` — **always prefer this** |
| Simple, guaranteed non-blocking | `invoke()`, with `async_invoke()` delegating to it |
| Blocking sync library | `async_invoke()` calling `await asyncio.to_thread(self.invoke, args, sly_data)` |

### The calling contract

- **`args`** — LLM-supplied parameter values, plus HOCON `args`, plus framework-injected
  keys (§5). Treat as read-only.
- **`sly_data`** — shared side-channel dict that never enters an LLM prompt. Largely
  read-only, but usable as a bulletin board — see `references/patterns.md`.
- **Return value** — goes directly into the chat stream. Return a `dict`, `list`, or `str`.

### Zero-argument constructor

The framework instantiates with `MyTool()`. Any `__init__` must take no required parameters.
Read configuration from env vars or from the `args` dict at call time.

```python
# OK
class BraveSearch(CodedTool):
    def __init__(self):
        self.api_key = os.getenv("BRAVE_API_KEY")

# NOT OK — the framework cannot call this
class MyTool(CodedTool):
    def __init__(self, api_key: str):
        ...
```

---

## 3. FILE PLACEMENT AND CLASS RESOLUTION

```
coded_tools/
├── my_network_name/          ← scoped to one agent network
│   ├── __init__.py
│   └── my_tool.py
├── shared_tool.py            ← available to all networks
└── utils/
    ├── __init__.py
    └── helper.py
```

`AGENT_TOOL_PATH` points at `coded_tools/` (default `<cwd>/coded_tools`).

Two setup rules, both of which fail loudly if you miss them:

- **Every directory needs an `__init__.py`** — including `coded_tools/` itself, not just the
  per-network subdirectories. Without the top-level one, class resolution reports the tool as
  not found even though the file exists.
- **`AGENT_TOOL_PATH` must be reachable from `PYTHONPATH`** — its *parent* directory has to be
  on the path. Otherwise startup fails with
  `ValueError: No reasonable agent tool path found in PYTHONPATH for <path>`.

Given `"class": "my_tool.MyTool"` inside a network named `my_network_name`, resolution is
tried in this order:

1. `my_tool.MyTool` — direct fully-qualified import
2. `coded_tools.my_network_name.my_tool.MyTool` — most specific
3. `coded_tools.my_tool.MyTool` — root shared
4. `my_tool.MyTool` — bare fallback

**Rule of thumb: use the short `module_filename.ClassName` form.** It works whether the file
sits in a network subdirectory or at the `coded_tools/` root.

With `AGENT_TOOL_PATH_ONLY=true`, resolution is restricted to the `AGENT_TOOL_PATH`
hierarchy and fully-qualified references stop working.

---

## 4. WIRING INTO HOCON

```hocon
{
    "name": "MyTool",
    "function": {
        "description": "Does X when given Y.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": { "type": "string",  "description": "The search query." },
                "limit": { "type": "int",     "description": "Max results to return." }
            },
            "required": ["query"]
        }
    },
    "class": "my_tool.MyTool",
    "args": { "limit": 10 }
}
```

**HOCON `args` win over LLM-supplied values for the same key.** Use them for hard defaults
and forced overrides; leave a key out of `args` if you want the LLM to control it.

An agent with `class` cannot be the front man.

---

## 5. FRAMEWORK-INJECTED ARGS

`args` is not only what the LLM sent. The framework adds these unless already present:

| Key | Value |
|---|---|
| `origin` | `List[Dict[str, Any]]` — the agent origin path |
| `origin_str` | `str` — this tool's full agent name |
| `progress_reporter` | A `ProgressJournal` for streaming progress to the client |
| `reservationist` | An `AccumulatingAgentReservationist` — only when the agent spec sets `allow.reservations` |

So a defensive `for key in args:` loop will see more than your declared parameters. Read the
keys you expect by name.

```python
progress = args.get("progress_reporter")
if progress is not None:
    await progress.async_report_progress({"step": 1}, "Fetching data…")
```

---

## 6. QUICK TEMPLATE

```python
import logging
from typing import Any
from typing import Dict
from typing import Union

from neuro_san.interfaces.coded_tool import CodedTool


class MyTool(CodedTool):
    """One-line description of what this tool does."""

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        logger = logging.getLogger(self.__class__.__name__)
        logger.debug("========== Calling %s ==========", self.__class__.__name__)

        query: str = args.get("query")
        if not query:
            return "Error: 'query' is required."

        api_key: str = sly_data.get("api_key")
        result = await do_work(query, api_key)

        logger.debug(">>> %s returning %s", self.__class__.__name__, result)
        return {"result": result}
```

More templates — async I/O, blocking libraries, env-var config, sly_data accumulation:
`references/patterns.md`.

---

## 7. HOUSE STYLE

Match the surrounding repo:

- **One `from x import y` per line** — ruff isort runs with `force-single-line`
- Logger obtained **inside** the method from `self.__class__.__name__`, not at module level
  (newer tools; older ones use a module-level `logger` — either is accepted)
- `%s`-style lazy logging args, never f-strings in log calls
- PEP 585 builtin generics (`dict[str, Any]`) in new code — the repo is Python ≥3.12
- Errors returned as `"Error: ..."` **strings**, not raised, so the LLM can recover
- **Never log `sly_data`** — it holds secrets

---

## 8. COMMON PITFALLS

| Mistake | Fix |
|---|---|
| `__init__` requires arguments | The framework calls `MyTool()` — no required params |
| Only `invoke()` defined, called async | Base `invoke()` returns `None` silently; add `async_invoke()` |
| `requests` called directly inside `async_invoke` | Wrap: `await asyncio.to_thread(self.invoke, args, sly_data)` |
| Writing to `args` | Read-only; use local variables |
| Logging `sly_data` | Never — it contains secrets |
| Missing `__init__.py` | Needed in `coded_tools/` **and** every subdirectory |
| `No reasonable agent tool path found in PYTHONPATH` | The parent of `AGENT_TOOL_PATH` must be on `PYTHONPATH` |
| sly_data missing in the tool | Check the calling agent's `allow.to_downstream.sly_data` |
| HOCON `args` not overriding | They do override; remove the key if the LLM should control it |
| Returning `None` | Return a `str` or `dict` |
| AAOSA fields on a coded tool | Coded tools are leaves and never speak AAOSA |
| Assuming `args` holds only your parameters | The framework injects four more keys (§5) |

---

## 9. CHECKLIST

- [ ] File at `coded_tools/<network>/my_tool.py` (or `coded_tools/` for shared)
- [ ] `__init__.py` in every subdirectory
- [ ] Class inherits `CodedTool`
- [ ] `async_invoke()` implemented (or `invoke()` plus a delegating `async_invoke()`)
- [ ] `__init__` takes no required parameters
- [ ] HOCON agent has `"class": "my_tool.MyTool"`
- [ ] HOCON `function.parameters` matches the keys the code reads from `args`
- [ ] `allow` declares any sly_data keys crossing a network boundary
- [ ] Unit test at `tests/coded_tools/<network>/test_my_tool.py`
- [ ] No hardcoded secrets — `os.getenv()` or `sly_data`
- [ ] `ns validate` passes on the network that uses it

---

## 10. REFERENCE FILES

| File | Read it when |
|---|---|
| `references/patterns.md` | You need a template, or args / sly_data / return-value patterns |
| `references/toolbox-registration.md` | Making the tool reusable across networks |
| `references/advanced.md` | Calling other agents, progress reporting, reservations |
| `references/testing.md` | Writing unit tests or integration fixtures |
| `references/env-vars.md` | Looking up an environment variable name |
