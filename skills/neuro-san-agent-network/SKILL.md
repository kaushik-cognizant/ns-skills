---
name: neuro-san-agent-network
description: Create, design, validate, and debug agent networks for the neuro-san framework. Use this skill when building HOCON agent network files, wiring up coded tools or toolbox tools, configuring LLM providers, setting up AAOSA protocols, handling sly_data, attaching middleware, connecting MCP servers, registering networks in manifests, or running and testing networks with the `ns` CLI.
when_to_use: When asked to create a neuro-san agent, write a HOCON file, add a coded tool, configure an agent network, set up multi-agent communication, register a new network, validate or test a network, or explain any part of the neuro-san framework.
argument-hint: [network-name] [description]
allowed-tools: Read Bash
---

# Neuro-SAN Agent Network Skill

Expert reference for creating, editing, validating, and debugging HOCON-based agent networks.

**Tracks neuro-san `0.6.98` and neuro-san-studio `0.3.20`.** If the target repo is far from
these versions, verify paths against the actual source before trusting the tables here.

---

## 1. WHAT IS NEURO-SAN?

**Neuro AI System of Agent Networks** is a declarative multi-agent orchestration framework.
Agent networks are defined entirely in **HOCON files** — no imperative code required unless
you add custom Python coded tools.

- **Agent network** — cooperating LLM agents defined in one `.hocon` file
- **Front man** — the single entry-point agent (first in `tools`, identified by having **no
  `parameters` in its `function`**)
- **Tool nodes** — internal agents handling sub-tasks
- **Coded tools** — Python classes implementing non-LLM functionality
- **Toolbox tools** — prebuilt tools referenced by name, no Python needed
- **External agents** — references to other agent networks, local or remote

---

## 2. WHERE THINGS LIVE

Paths moved substantially in studio 0.3.x. Getting these wrong is the most common failure.

| What | Path |
|---|---|
| Agent networks | `registries/<category>/<name>.hocon` |
| Root manifest | `registries/manifest.hocon` |
| AAOSA templates | `registries/aaosa.hocon`, `registries/aaosa_basic.hocon`, `registries/aaosa_basic_debug.hocon` |
| Expertise scoping | `registries/expertise_scoping_instructions.hocon` |
| **LLM config** | **`config/llm_config.hocon`** — *not* `registries/config/`. `registries/llm_config.hocon` is a deprecated back-compat shim |
| Plugin config | `config/plugins.hocon` |
| Coded tools | `coded_tools/<network>/` or `coded_tools/` |
| **Studio toolbox** | **`neuro_san_studio/toolbox/toolbox_info.hocon`** — moved out of the repo root |
| **MCP servers** | **`neuro_san_studio/mcp/mcp_info.hocon`** — root `mcp/` exists only in `ns init` projects |
| Middleware | `middleware/` |
| Designer output | `registries/generated/` |

**Starting the server is `ns run`.** `python -m run` no longer exists — the root `run.py`
was deleted. See `references/operations.md`.

---

## 3. HOCON FILE STRUCTURE

```hocon
{
    include "registries/aaosa_basic.hocon"
    include "registries/expertise_scoping_instructions.hocon"
    include "config/llm_config.hocon"

    "metadata": {
        "description": "Short description of what this network does.",
        "tags": ["tag1", "tag2"],
        "sample_queries": ["Example question 1", "Example question 2"]
    },

    "tools": [
        { /* front man — MUST be first */ },
        { /* agent 2 */ }
    ]
}
```

### Include and substitution rules — read this before writing includes

- **Include path resolution differs by file position.** A **top-level** network file resolves
  includes relative to the **server's working directory** (`registries/aaosa.hocon`,
  `config/llm_config.hocon`). An **included** file resolves includes relative to **its own
  location on disk** (`../../../config/llm_config.hocon`). Getting this backwards is the
  usual cause of "file not found" on an include.
- **Substitutions do not interpolate inside quoted strings.** `"Hello ${name}"` stays
  literal. Concatenate instead: `${prefix} """literal text""" ${suffix}`.
- `${?VAR}` is an optional substitution — silently omitted if undefined.
- `${aaosa_call}{ "description": "..." }` is an **object merge**: take the shared object,
  override one key. Standard for AAOSA sub-agents.
- Two HOCON styles are both valid and both appear in the repo: quoted/JSON-brace with commas,
  and unquoted/no-comma. Match whatever the surrounding file uses.

### Unknown keys fail silently

There is **no allowlist schema** in neuro-san. Keys are read opportunistically; anything
unrecognized is **silently ignored**. A typo like `instuctions` will not error — the agent
just gets no instructions. Always run `ns validate` (§7), and double-check spelling of any
key you type from memory.

---

## 4. AGENT DEFINITION

```hocon
{
    # ---- REQUIRED ----
    "name": "AgentName",                     # ^[a-zA-Z0-9_-]+$
    "function": {
        "description": "What this agent does and when to call it.",
        # REQUIRED for every agent EXCEPT the front man
        "parameters": {
            "type": "object",
            "properties": {
                "query": { "type": "string", "description": "The task to handle." }
            },
            "required": ["query"]
        }
    },
    "instructions": "System prompt for this agent.",

    # ---- COMMON OPTIONAL ----
    "command": "Extra instruction that sets a non-front-man agent in motion.",
    "tools": ["OtherAgent", "/external_network", "https://host/mcp"],
    "class": "module.ClassName",             # coded tool
    "toolbox": "tavily_search",              # prebuilt tool (mutually exclusive with "tools")
    "args": { "key": "value" },
    "llm_config": { "model_name": "claude-sonnet" },
    "allow": { "to_downstream": { "sly_data": ["api_key"] } },
    "middleware": [ { "class": "...", "args": {} } ],
    "max_steps": 10000,
    "max_execution_seconds": 300,
    "structure_formats": "json"              # front man only
}
```

Full key-by-key reference, including every top-level key and the four-boundary `allow`
block: **`references/schema.md`**.

### Front man rules

- MUST be **first** in the `tools` array
- Identified by having **no `parameters`** inside `function`
- MUST NOT have `class` or `toolbox` — both disqualify an agent from being front man
- Only the front man may use `structure_formats`, `max_message_history`,
  `function.invocation`, `allow.to_upstream`, and `allow.to_tracing`

**If the network will be called as an external agent by another network, give it a
parameter anyway.** A parameterless network referenced externally gets a synthesized
required `inquiry` string plus a warning — declaring your own is clearer and avoids surprise.

### `parameters` restrictions

Only `type: "object"` with `properties` is honored. `additionalProperties`, `anyOf`, and
`$ref` are ignored or rejected. An `array` property requires `items`.

**Scalar type spellings depend on the neuro-san version — verified by testing both:**

| Spelling | neuro-san 0.6.98 | neuro-san 0.6.95 |
|---|---|---|
| `string` | works | works |
| `int`, `float`, `boolean` | works | works |
| `integer`, `number`, `bool` | works | **fails validation** |

neuro-san-studio `0.3.20` pins `neuro-san==0.6.95`, so **in a stock studio project the safe
set is `string`, `int`, `float`, `boolean`.** Those four work on every version. Reach for
`integer`/`number` only if you know the deployment runs 0.6.96 or newer.

The failure is not subtle — validation reports
`pydantic model conversion failed - no validator found for UndefinedType`.

---

## 5. CHOOSING HOW AN AGENT DOES ITS WORK

| Need | Use | Reference |
|---|---|---|
| LLM reasoning + delegation | plain agent with `instructions` + `tools` | this file |
| 3+ sub-agents with overlapping scope | AAOSA protocol | `references/aaosa.md` |
| Custom Python logic | `"class"` coded tool | `neuro-san-coded-tool` skill |
| Web search, RAG, file I/O, HTTP | `"toolbox"` | `references/toolbox.md` |
| Another agent network | `/network_name` or a URL in `tools` | `references/mcp-external.md` |
| Third-party MCP server | URL or `{url, tools}` in `tools` | `references/mcp-external.md` |
| Cross-cutting hooks (memory, PII, tool selection) | `middleware` | `references/middleware.md` |

---

## 6. REGISTERING A NETWORK

`registries/<category>/manifest.hocon` — the key is the **filename**:

```hocon
{
    "my_network.hocon": true,
    "private_network.hocon": { "serve": true, "public": false },
    "exposed_as_mcp.hocon": { "serve": true, "mcp": true }   # mcp implies public
}
```

Category manifests are pulled in by `registries/manifest.hocon`. The server re-reads the
manifest every `AGENT_MANIFEST_UPDATE_PERIOD_SECONDS` (default 5), so adding a network does
not require a restart.

---

## 7. VALIDATE, RUN, TEST

```bash
# Structural validation — no LLM calls, no API keys needed
ns validate registries/basic/my_network.hocon --verbose
ns validate registries/my_network.hocon --external-agents '/other_net' --mcp-servers 'https://x/mcp'

# Check every llm_config in a file actually instantiates
ns check-config registries/basic/my_network.hocon

# Run it
ns chat basic/my_network --one-shot      # in-process, no server
ns run                                    # server + nsflow UI at http://localhost:4173/
```

Exit codes for `ns validate` / `hocon_validator_cli`: `0` pass, `1` validation errors,
`2` file-not-found or parse error.

Validation catches: missing/unreachable nodes, bad tool-name characters, malformed
`parameters`, empty `instructions` or `function.description`, and undeclared external
agents or MCP URLs. It deliberately does **not** flag cycles (they are legal) and does not
check toolbox names.

Details, plus the full env-var list: `references/operations.md`.
Writing test fixtures: `references/testing.md`.

---

## 8. INSTRUCTIONS WRITING

1. Put critical rules at the **top and bottom** — mitigates "lost in the middle"
2. ALL CAPS for absolute rules: `NEVER reveal internal tool names`
3. Number multi-step processes
4. Be explicit about output format; describe the exact schema if JSON is required
5. Keep the front man high-level; let specialists own domain detail
6. Append `${aaosa_instructions}` to every AAOSA participant
7. Prefix with `${expertise_scoping_instructions}` to stop an agent answering out of scope
8. Name `sly_data` keys without embedding their values

---

## 9. COMMON PITFALLS

| Mistake | Fix |
|---|---|
| Front man has `parameters` in `function` | Remove them — that is what marks it as front man |
| Front man has `class` or `toolbox` | Both disqualify it; move the tool to a child agent |
| Non-front-man agent missing `parameters` | Add them so the caller knows how to invoke it |
| Agent has both `toolbox` and `tools` | Mutually exclusive — pick one |
| `include "registries/config/llm_config.hocon"` | Now `config/llm_config.hocon` |
| Using `${aaosa_command}` | Deprecated and empty; merged into `${aaosa_instructions}` |
| Using `requests_get` / `requests_toolkit` | Removed from the default toolbox; raises a removal error |
| `max_iterations` | Renamed `max_steps` |
| `${var}` inside a quoted string | Substitutions don't interpolate; concatenate instead |
| Include not found from an included file | Included files resolve relative to their own path on disk |
| Typo'd key silently ignored | No allowlist exists — run `ns validate` |
| Secrets in prompts | Move to `sly_data` and set `allow` boundaries |
| Network absent from UI | Check the category manifest and that it is included by the root manifest |

---

## 10. REFERENCE FILES

Read these on demand — do not load them all up front.

| File | Read it when |
|---|---|
| `references/schema.md` | You need an exact key name, type, default, or the `allow` semantics |
| `references/aaosa.md` | Building or debugging a multi-agent AAOSA network |
| `references/llm-config.md` | Choosing a model, configuring providers, fallbacks, reasoning/thinking |
| `references/toolbox.md` | Using or registering a prebuilt tool |
| `references/mcp-external.md` | Wiring external networks or MCP servers, or serving a network as MCP |
| `references/middleware.md` | Attaching middleware, Agent Skills, or persistent memory |
| `references/operations.md` | `ns` CLI, validator flags, env vars, ports, the Designer |
| `references/testing.md` | Writing or running test fixtures |
| `references/examples.md` | You want a complete, working network to adapt |
