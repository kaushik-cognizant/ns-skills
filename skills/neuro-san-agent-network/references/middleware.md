# Middleware, Agent Skills, and Memory Reference

Middleware wraps agent and LLM calls with cross-cutting behavior — memory, PII redaction,
tool selection, persistence.

**There is no neuro-san middleware base class.** The base is LangChain's `AgentMiddleware`
(`langchain.agents.middleware.types`), pinned at `langchain>=1.2.0,<2.0`. Only **class-based**
middleware is supported — not the decorator form.

---

## Wiring

```hocon
"middleware": [
    { "class": "middleware.persistent_memory.persistent_memory_middleware.PersistentMemoryMiddleware",
      "args": { "store": "json_file", "sly_data": true } },
    { "class": "langchain.agents.middleware.PIIMiddleware",
      "args": { "pii_type": "email", "strategy": "redact", "apply_to_output": true } }
]
```

**Order matters — the first entry is outermost.** Entries missing a `class`, or whose config
isn't a dict, are skipped with a warning rather than failing the load.

Per-entry keys: `class` (required, fully-qualified), `args`, `checkpointer` (a nested
`{class, args}`; multiple checkpointers warn and the first wins), and `allow.reservations`.

---

## Hook methods

Override the async forms in a server context.

| Sync | Async | Fires |
|---|---|---|
| `before_agent` | `abefore_agent` | Before the agent starts |
| `before_model` | `abefore_model` | Before each LLM call |
| `after_model` | `aafter_model` | After each LLM call |
| `after_agent` | `aafter_agent` | After the agent finishes |
| `wrap_model_call` | `awrap_model_call` | Intercept/replace an LLM call |
| `wrap_tool_call` | `awrap_tool_call` | Intercept/replace a tool call |

`before_*`/`after_*` take `(state, runtime)` and return `dict | None`. The `wrap_*` forms take
`(request, handler)` and must invoke or replace `handler`.

Class attributes available: `state_schema`, `tools`, `trace_policy`, `transformers`, `name`.

Control flow is available through `@hook_config(can_jump_to=[...])` plus returning
`{"jump_to": "end" | "model" | "tools"}`.

---

## Framework-injected args

Declared in `args` with any placeholder value (e.g. `true`), then replaced at construction.
**The key must already be present in your `args` dict** or nothing is injected.

| Key | Injected value |
|---|---|
| `sly_data` | The request's sly_data dict |
| `chat_history` | `List[BaseMessage]` |
| `origin` / `origin_str` | Agent origin path / full name |
| `progress_reporter` | `ProgressJournal` |
| `journal` | `OriginatingJournal` (undocumented upstream) |
| `activation_capsule` | `ActivationCapsule` — lets middleware call other agents (undocumented upstream) |
| `reservationist` | `AccumulatingAgentReservationist`; needs `allow.reservations` |

```hocon
{ "class": "...", "allow": { "reservations": true },
  "args": { "reservationist": true, "sly_data": true } }
```

---

## Shipped middleware

### In neuro-san core (`neuro_san/middleware/`)

- `llm_config_tool_selector_middleware.LlmConfigToolSelectorMiddleware` — LLM-driven tool
  narrowing. Args: `activation_capsule`, `llm_config` (supports `fallbacks`), `sly_data`,
  `system_prompt`, `max_tools`, `always_include`. Also *denies* unadvertised tool calls at
  execution time, which the LangChain superclass alone does not do.
- `network_copy_middleware.NetworkCopyMiddleware` — args `reservationist`, `sly_data`
- `neuro_san_summarization_middleware.NeuroSanSummarizationMiddleware` — conversation
  summarization

### In neuro-san-studio (`middleware/`)

- `persistent_memory/` — see below
- `agent_skills_middleware.AgentSkillsMiddleware` — see below
- `agent_checklist_middleware`
- `agent_network_designer/` — persistence, assembly, and validation for the Designer

### From LangChain

`langchain.agents.middleware.PIIMiddleware` is used directly. Args: `pii_type`, `detector`
(regex), `strategy` (e.g. `redact`), `apply_to_input`, `apply_to_output`.

---

## Agent Skills

`AgentSkillsMiddleware` implements the [agentskills.io](https://agentskills.io/specification)
spec, letting a network load `SKILL.md` files with progressive disclosure — the skill's
summary stays in context and full content is fetched on demand.

```hocon
"middleware": [
    { "class": "middleware.agent_skills_middleware.AgentSkillsMiddleware",
      "args": {
          "skill_sources": ["skills/my_skill", "https://example.com/skill"],
          "keep_skill_in_context": false,
          "http_timeout": 30
      } }
]
```

Tools it exposes to the agent: `get_full_skill_content`, `load_skill_resource_local`,
`load_skill_resource_remote`. Examples: `registries/basic/job_guessing_skill.hocon`,
`registries/basic/internal_communication_skill.hocon`.

---

## Persistent memory

```hocon
"middleware": [
    { "class": "middleware.persistent_memory.persistent_memory_middleware.PersistentMemoryMiddleware",
      "args": { "store": "json_file", "summarization": true, "sly_data": true } }
]
```

Backends: `json_file` (default), `markdown_file`, `mem0`. Operations: create, read, append,
delete, search, list. Summarization is opt-in.

`mem0` requires `args.sly_data: true` so memory can be scoped per `user_id`.

---

## Reservations

`allow.reservations: true` grants a `reservationist` — an `AccumulatingAgentReservationist`
for building temporary/ephemeral agent networks at runtime. It appears both on an agent spec
(injected into a coded tool's `args`) and on an individual middleware entry.

The `Reservationist` interface: `reserve(lifetime_in_seconds, prefix) -> Reservation`,
`deploy(deployment_dict, confirmation)`, `deploy_one(...)`,
`validate_with(external_networks, mcp_servers)`. It is an async context manager. Default
lifetime is 24 hours.

This is undocumented in the upstream HOCON reference; working examples are
`registries/agent_network_designer.hocon` and `neuro_san/registries/copy_cat.hocon`.
