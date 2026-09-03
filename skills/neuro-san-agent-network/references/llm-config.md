# LLM Configuration Reference

Source of truth: `neuro_san/internals/run_context/langchain/llms/default_llm_info.hocon`.
Schema for extending it: `neuro-san/docs/llm_info_hocon_reference.md`.

**Default model is `gpt-5.2`.** (Some upstream prose still says `gpt-4o` or
`gpt-3.5-turbo` — those strings are stale; `default_config.model_name` is `gpt-5.2`.)

---

## Placement

```hocon
# Network-level — applies to every agent
"llm_config": { "model_name": "gpt-5.2", "temperature": 0.7 }

# Agent-level — overlaid on top of the network-level config
{ "name": "Analyst", "llm_config": { "model_name": "claude-opus" }, ... }
```

Studio projects normally pull a shared config instead of inlining:

```hocon
include "config/llm_config.hocon"
```

which by default chains to `config/developer_llm_config.hocon` — an OpenAI → Anthropic →
Gemini `fallbacks` chain (`gpt-5.2` / `claude-sonnet` / `gemini-3-flash`). Sibling profiles:
`cluster_llm_config.hocon`, `byok_llm_config.hocon`, `private_llm_config.hocon`.

---

## Model names

### OpenAI — `class: "openai"`

```
gpt-5.6-sol   gpt-5.6-terra   gpt-5.6-luna
gpt-5.5-pro   gpt-5.5
gpt-5.4-pro   gpt-5.4   gpt-5.4-mini   gpt-5.4-nano
gpt-5.2   gpt-5.1   gpt-5   gpt-5-mini
gpt-4.1   gpt-4o   gpt-4o-mini   gpt-4-turbo
gpt-4                          (no tool-calling)
gpt-3.5-turbo, gpt-3.5-turbo-16k   (no tool-calling)
o1   o3-mini
```

### Anthropic — `class: "anthropic"`

Floating aliases that always resolve to the latest version — **prefer these**:

| Alias | Resolves to |
|---|---|
| `claude-haiku` | `claude-haiku-4-5-20251001` |
| `claude-sonnet` | `claude-sonnet-5` |
| `claude-opus` | `claude-opus-5` |
| `claude-fable` | `claude-fable-5-1` |

Concrete entries:

| Model | Context | Max output | $/1k in | $/1k out |
|---|---|---|---|---|
| `claude-haiku-4-5-20251001` | 200k | 64k | 0.001 | 0.005 |
| `claude-sonnet-4-5-20250929` | 200k | 64k | 0.003 | 0.015 |
| `claude-sonnet-4-6` | 200k | 64k | 0.003 | 0.015 |
| `claude-sonnet-5` | 1M | 128k | 0.003 | 0.015 |
| `claude-opus-4-5-20251101` | 200k | 64k | 0.005 | 0.025 |
| `claude-opus-4-6` | 200k | 128k | 0.005 | 0.025 |
| `claude-opus-4-7` | 1M | 128k | 0.005 | 0.025 |
| `claude-opus-4-8` | 1M | 128k | 0.005 | 0.025 |
| `claude-opus-5` | 1M | 128k | 0.005 | 0.025 |
| `claude-fable-5` | 1M | 128k | 0.010 | 0.050 |
| `claude-fable-5-1` | 1M | 128k | 0.010 | 0.050 |

### Anthropic via Bedrock — `class: "anthropic-bedrock"`

Recommended over the legacy `bedrock` class for Claude. Supports `thinking`, `effort`,
`mcp_servers`, `context_management`.

```
bedrock-claude-opus    → global.anthropic.claude-opus-5
bedrock-claude-sonnet  → global.anthropic.claude-sonnet-5
bedrock-claude-haiku   → global.anthropic.claude-haiku-4-5-20251001-v1:0
global.anthropic.claude-opus-5      global.anthropic.claude-opus-4-8
global.anthropic.claude-sonnet-5    global.anthropic.claude-sonnet-4-6
```

Swap the `global.` prefix for `us.`, `eu.`, or `apac.` as needed.

### Legacy Bedrock — `class: "bedrock"`

One entry remains: `bedrock-us-claude-sonnet-4` → `us.anthropic.claude-sonnet-4-20250514-v1:0`.

### Google Gemini — `class: "gemini"`

```
gemini-3.7-flash   gemini-3.6-flash   gemini-3.5-flash   gemini-3.5-flash-lite
gemini-3.1-pro     gemini-3.1-flash-lite   gemini-3.1-pro-customtools
gemini-3-flash
gemini-2.5-pro     gemini-2.5-flash   gemini-2.5-flash-lite
```

### Azure OpenAI — `class: "azure-openai"`

```
azure-gpt-5.4   azure-gpt-5.4-mini   azure-gpt-5.4-nano   azure-gpt-5.4-pro
azure-gpt-4.1   azure-gpt-4o   azure-gpt-4o-mini   azure-gpt-4
azure-gpt-3.5-turbo   azure-o1   azure-o3-mini
```

### OpenRouter — `class: "openrouter"`

`provider/model` naming, plus two meta-routers: `openrouter/free`, `openrouter/auto`.

### Ollama — `class: "ollama"`

```
llama3.1   llama3.3   mistral   mistral-nemo   mixtral
qwen2.5:14b   qwen3:8b   gemma4:e4b
llama2*  llama3*  llama3:70b*  llava*  deepseek-r1:14b*     (* = no tool-calling)
```

### NVIDIA — `class: "nvidia"`

```
nvidia-llama-3.1-405b-instruct   nvidia-llama-3.3-70b-instruct
nvidia-deepseek-r1               (no tool-calling)
```

> Models without the `tools` capability **cannot be a front man or a branch node** — they
> can't call other agents. Use them only as leaf responders.

---

## `llm_config` fields

Universal: `model_name`, `class`, `fallbacks`, `prompt_token_fraction`, `max_tokens`, `verbose`.

`class` is either a known key (`openai`, `azure-openai`, `anthropic`, `anthropic-bedrock`,
`bedrock`, `gemini`, `nvidia`, `ollama`, `openrouter`) or a fully-qualified LangChain chat
class path.

Provider-specific highlights:

- **openai** — `temperature`, `max_tokens`, `top_p`, `seed`, `reasoning`, `reasoning_effort`,
  `verbosity`, `presence_penalty`, `frequency_penalty`, `logit_bias`, `request_timeout`,
  `max_retries`, `stop`, `openai_api_key`, `openai_api_base`
- **anthropic** — `max_tokens`, `temperature`, `top_k`, `top_p`, `stop_sequences`,
  `thinking`, `effort`, `anthropic_api_key`, `anthropic_api_url`, `max_retries`.
  Also accepted though undeclared: `default_headers`, `betas`, `mcp_servers`,
  `context_management`
- **gemini** — `temperature` (default 0.7), `max_tokens`, `top_k`, `top_p`,
  `thinking_level`, `thinking_budget`, `google_api_key`, `max_retries` (default 6)
- **azure-openai** (extends openai) — `azure_endpoint`, `deployment_name`,
  `openai_api_version`, `azure_ad_token`, `model_version`
- **anthropic-bedrock** (extends anthropic) — `region_name`, `aws_access_key_id`,
  `aws_secret_access_key`, `aws_session_token`
- **ollama** — `base_url`, `num_ctx`, `num_predict`, `temperature`, `top_k`, `top_p`,
  `repeat_penalty`, `mirostat`, `keep_alive`, `reasoning`

---

## Reasoning and thinking

```hocon
# OpenAI
"llm_config": { "model_name": "gpt-5.4", "reasoning_effort": "high" }

# Anthropic — budget form
"llm_config": {
    "model_name": "claude-sonnet",
    "thinking": { "type": "enabled", "budget_tokens": 10000 }
}

# Anthropic — adaptive form (the ONLY mode accepted on Opus 4.7+)
"llm_config": { "model_name": "claude-opus", "thinking": { "type": "adaptive" } }

# Gemini
"llm_config": { "model_name": "gemini-3-flash", "thinking_level": "medium" }
```

Anthropic specifics:

- `thinking`: omit, or `{"type":"enabled","budget_tokens":N}` (N ≥ 1024), or
  `{"type":"adaptive"}`, or `{"type":"disabled"}`
- **`budget_tokens` returns a 400 on Opus 4.7 and newer** — use `adaptive` there
- `effort`: `max` | `xhigh` | `high` | `medium` | `low`. `high` is the same as omitting.
  `max` is Opus 4.6 only; `xhigh` is Opus 4.7 only

---

## Fallbacks

Tried in order when a model errors or is unavailable:

```hocon
"llm_config": {
    "fallbacks": [
        { "model_name": "gpt-5.2" },
        { "model_name": "claude-sonnet" },
        { "model_name": "gemini-3-flash" }
    ]
}
```

A **nested list is a peer group whose members are tried in random order** — useful for
spreading load across equivalent models:

```hocon
"fallbacks": [
    [ { "model_name": "gpt-5.2" }, { "model_name": "claude-sonnet" } ],   # randomized peers
    { "model_name": "gemini-3-flash" }                                     # only if both fail
]
```

`fallbacks` cannot nest inside `fallbacks`. Verify a chain works with `ns check-config`.

---

## Client-provided API keys

Any `llm_config` value literally equal to `"sly_data"` (case-insensitive) is replaced at
runtime from `sly_data["llm_config"][<same key>]`. This lets a client bring its own key
without it ever entering a prompt:

```hocon
"llm_config": { "model_name": "gpt-5.2", "openai_api_key": "sly_data" }
```

---

## Extending the catalog

Add models via a `llm_info_file` key in the network HOCON, or the `AGENT_LLM_INFO_FILE` env
var — the HOCON key wins. Per-model fields: `class`, `use_model_name`, `modalities`,
`capabilities`, `context_window_size`, `max_output_tokens`, `knowledge_cutoff`,
`price_per_1k_input_tokens`, `price_per_1k_output_tokens`, `model_launch_date`,
`model_retirement_date`.

The two price fields are the only source of token-cost reporting; they default to 0 with a
warning if omitted.

For tests without an LLM: `class: "neuro_san.test.llms.chat_mock_llm.ChatMockLlm"` with
`model_name: "echo"`.
