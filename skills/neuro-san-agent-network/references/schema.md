# HOCON Schema Reference

Mirrors `neuro-san/docs/agent_hocon_reference.md`. Verified against neuro-san `0.6.98`.

> **There is no allowlist.** No closed schema, no unknown-key rejection. Keys are read
> opportunistically via `dict.get()`. Anything unrecognized is silently ignored, so a
> misspelled key produces no error — just missing behavior.

---

## Top-level keys

| Key | Type | Default | Purpose |
|---|---|---|---|
| `tools` | list | — | **Required.** Agent specs. First element is the front man. |
| `llm_config` | dict | — | Default LLM for all agents; per-agent config overlays it. |
| `metadata` | dict | — | `description`, `tags`, `sample_queries`. Informational only. |
| `commondefs` | dict | — | `replacement_strings`, `replacement_values` for substitution. |
| `verbose` | bool \| str | `false` | `true`, `"extra"`, `"logging"` add a logging callback handler. |
| `max_steps` | int | `10000` | LangGraph recursion / super-step limit. |
| `max_iterations` | int | — | **Deprecated** alias for `max_steps`; logs a warning. |
| `max_execution_seconds` | float | `300.0` | Wall-clock limit. |
| `max_attempts` | int | `3` | Retries on retryable errors. Distinct from `max_steps`. |
| `error_formatter` | str | `"string"` | `"string"` or `"json"` (keys `error`, `tool`, `details`). |
| `error_fragments` | list[str] | — | Substrings in agent output that mark it as an error. |
| `sly_data_schema` | dict | — | Merged into the **front man's** `function.sly_data_schema`. |
| `llm_info_file` | str | — | Extra LLM catalog HOCON. Beats `AGENT_LLM_INFO_FILE`. |
| `toolbox_info_file` | str | — | Extra toolbox HOCON. Beats `AGENT_TOOLBOX_INFO_FILE`. |
| `request_timeout_seconds` | float | `0.0` | `0.0` = no timeout. |
| `context_type` | str | — | Rarely used; `"openai*"` / `"langchain*"`. |

Most of these also work per-agent; the top-level value is inherited unless overridden.

---

## Per-agent keys

| Key | Type | Notes |
|---|---|---|
| `name` | str | Required unless `function.name` is set. Must match `^[a-zA-Z0-9_-]+$`. |
| `function` | dict \| str | Tool contract. **Absence marks the front man.** A string value references `commondefs.replacement_values`. |
| `function.description` | str | Must be a non-empty string if present. |
| `function.name` | str | Overrides `name`. |
| `function.parameters` | dict | JSON Schema. Only `{type:"object", properties, required}` is honored. |
| `function.sly_data_schema` | dict | Advertises expected input sly_data. Front-man convention. |
| `function.sly_data_output_schema` | dict | Advertises returned sly_data. |
| `function.invocation` | str \| dict | `"chatbot"` (default) or `"event"`. Front man only. As a dict, the value is read from `invocation_type`. |
| `instructions` | str | System prompt. Non-empty if present. Required for LLM agents. |
| `command` | str | Sets a non-front-man LLM agent in motion. |
| `tools` | list | Downstream agents, `/external_agents`, URLs, MCP dicts. |
| `class` | str | CodedTool. Disqualifies front-man status. |
| `toolbox` | str | Toolbox entry name. Disqualifies front-man status. **Cannot combine with `tools`.** |
| `args` | dict | Hard-coded args. **These win over LLM-supplied args.** |
| `args.tools` | dict \| list | Declares agents a CodedTool calls programmatically, so connectivity reporting sees them. |
| `llm_config` | dict | Per-agent override, overlaid on network-level. |
| `middleware` | list[dict] | See `middleware.md`. Order matters — first is outermost. |
| `allow` | dict | Security policy. See below. |
| `display_as` | str | Overrides auto-detection: `llm_agent`, `coded_tool`, `langchain_tool`, `external_agent`. |
| `max_message_history` | int | **Front man only.** Caps returned chat context. Default unlimited. |
| `structure_formats` | str \| list[str] | **Front man only.** Only `"json"` is implemented. A bare string is accepted. |
| `verbose`, `max_steps`, `max_execution_seconds`, `max_attempts`, `error_formatter`, `error_fragments` | | Same meaning as top-level. |

### Which handler an agent gets

Resolved in this order — the first match wins:

1. **External** — the name is a `/reference` or a URL
2. **Toolbox** — `toolbox` is set
3. **Coded tool** — `function` and `class` are both set
4. **Branch** — `function` set, `class` not set (an ordinary LLM agent)
5. **Front man** — `function` absent

---

## The `allow` block

Four boundaries plus two agent-level flags.

```hocon
"allow": {
    "connectivity": true,
    "to_downstream":   { "sly_data": ["api_key", "user_id"] },
    "from_downstream": { "sly_data": ["child_result"],
                         "messages": ["/child_network"] },
    "to_upstream":     { "sly_data": ["output_token"] },
    "to_tracing":      { "sly_data": ["run_id"] }
}
```

| Key | Scope | Default | Meaning |
|---|---|---|---|
| `connectivity` | any agent | `true` | `false` hides this node's downstream tools from connectivity reports |
| `to_downstream.sly_data` | any agent | nothing | What flows **to** external agents |
| `from_downstream.sly_data` | any agent | nothing | What flows **back from** external agents |
| `from_downstream.messages` | any agent | `false` | Which external agents' internal messages surface. Value is the reference **as written in `tools`** |
| `to_upstream.sly_data` | **front man** | nothing | What flows back to the client |
| `to_tracing.sly_data` | **front man** | keys shown, values `<redacted>` | Opt in per key to send real values to tracing |
| `reservations` | coded-tool agent, or a middleware entry | `false` | Grants a `reservationist` for ephemeral networks |

Security is deny-by-default: absent, `false`, or `{}` all mean nothing passes.

### `sly_data` value forms

| Form | Effect |
|---|---|
| `true` | Everything through |
| `false` / absent / `{}` | Nothing through |
| `["k1", "k2"]` | Only those keys |
| `{"k1": true, "k2": false, "secret": "api_key"}` | `true` passes as-is, `false` blocks, **a string value passes the key through under that new name** |

Only **top-level** keys are considered — nested dict keys are not filtered individually.

### Undocumented aliases

Present in code, absent from the upstream doc. Prefer the modern spelling.

- `allow.sly_data` — legacy alias for `allow.to_downstream.sly_data`, lower precedence
- `allow.from_downstream.reporting` — alias for `messages`, lower precedence

---

## `parameters` rules

```hocon
"parameters": {
    "type": "object",
    "properties": {
        "text":    { "type": "string",  "description": "..." },
        "count":   { "type": "int",     "description": "..." },
        "ratio":   { "type": "float",   "description": "..." },
        "enabled": { "type": "boolean", "description": "..." },
        "tags":    { "type": "array", "items": { "type": "string" }, "description": "..." },
        "options": { "type": "object", "properties": { "mode": { "type": "string" } } }
    },
    "required": ["text"]
}
```

- Top-level `type` must be `"object"`
- `additionalProperties`, `anyOf`, `$ref` are ignored or rejected
- `array` requires `items`
- Every name in `required` must exist in `properties` — the validator checks this

### Scalar type spellings are version-dependent

Verified by running the validator against both versions:

| Spelling | 0.6.98 | 0.6.95 |
|---|---|---|
| `string` | works | works |
| `int` | works | works |
| `float` | works | works |
| `boolean` | works | works |
| `integer` | works | **fails** |
| `number` | works | **fails** |
| `bool` | works | **fails** |

neuro-san-studio `0.3.20` pins `neuro-san==0.6.95`. **In a stock studio project, use
`string`, `int`, `float`, `boolean`** — that set is safe on every version.

On an affected version the error is:

```
pydantic model conversion failed - no validator found for
<class 'pydantic.v1.fields.UndefinedType'>, see `arbitrary_types_allowed` in Config
```

The studio's own registries reflect this: `int` (10 uses) and `float` (9) dominate, and the
handful of `integer`/`number` uses would fail against the pinned version.

---

## `commondefs`

Define once, reference by name from any agent:

```hocon
"commondefs": {
    "replacement_strings": {
        "instructions_prefix": "You are part of a customer support network."
    },
    "replacement_values": {
        "shared_function": { "description": "...", "parameters": { ... } }
    }
}
```

A `function` whose value is a **string** is resolved from `replacement_values`.

An equally common idiom is a plain top-level key used purely as a substitution source — not
a schema key, just HOCON:

```hocon
"instructions_prefix": """You are part of a support team.""" ${expertise_scoping_instructions},
...
"instructions": ${instructions_prefix} """Your specific role here.""" ${aaosa_instructions}
```
