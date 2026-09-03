# Operations Reference — CLI, Validation, Environment

---

## The `ns` CLI

Installed by neuro-san-studio as both `ns` and `neuro-san-studio`; also runnable as
`python -m neuro_san_studio <subcommand>`. `ns --version` / `-V` prints the version.

**`python -m run` is gone.** The root `run.py` was deleted.

| Command | Purpose |
|---|---|
| `ns init` | Scaffold a starter project in the current directory |
| `ns run` | Start the neuro-san server + nsflow UI |
| `ns chat AGENT` | Chat with a network, in-process — no server needed |
| `ns validate HOCON_PATH` | Structural validation of a network file |
| `ns check-llm-keys` | Validate LLM API keys |
| `ns check-config` | Instantiate and call every `llm_config` in a file |
| `ns import NETWORKS...` | Import networks + dependencies from the installed package |
| `ns export NETWORK` | Bundle a network + deps into `.hocon` or `.zip` |
| `ns internalize-agents INPUT` | Inline external refs into one self-contained file |

### `ns init`

`--providers openai,anthropic,google` skips the interactive prompt. Creates
`registries/manifest.hocon`, `registries/generated/manifest.hocon`, the AAOSA + expertise
includes, `registries/manifest_and.hocon`, `mcp/mcp_info.hocon`, `config/plugins.hocon`,
and `config/llm_config.hocon`, then imports the default networks.

Provider defaults: `openai` → `gpt-5.2`, `anthropic` → `claude-sonnet`,
`google` → `gemini-3-flash`. Multiple providers produce a `fallbacks` chain.

Note it does **not** create a project-local `toolbox/` — the toolbox resolves to the packaged
one.

### `ns run`

Flags: `--server-host`, `--server-http-port`, `--nsflow-port`, `--log-level`,
`--thinking-file`, `--client-only`, `--server-only`. Unknown extra args are forwarded.

Mutually exclusive: `--client-only` with `--server-only`; `--client-only` with
`--server-host`/`--server-http-port`; `--server-only` with `--nsflow-port`.

- neuro-san server → `localhost:8080`
- nsflow UI → <http://localhost:4173/>
- Logs → `logs/server.log`, `logs/nsflow.log`, `logs/thinking_dir/`, `logs/agent_thinking.txt`

Port conflicts are detected up front and the CLI offers to kill the occupying process.

### `ns chat`

```bash
ns chat basic/music_nerd                    # interactive, in-process
ns chat basic/music_nerd --one-shot
ns chat my_net --connection http --host localhost --port 8080
ns chat --list                              # list available agents
```

Extra args are forwarded to `neuro_san.client.agent_cli` (`--tag`, `--connectivity`,
`--first_prompt_file`, `--sly_data '<json>'`, …).

---

## Validation

```bash
ns validate registries/basic/my_network.hocon --verbose
ns validate registries/my_network.hocon \
    --external-agents '/agent_one,/agent_two' \
    --mcp-servers 'https://mcp.example.com/mcp' \
    --registry-dir /path/to/project
```

Equivalent core module: `python -m neuro_san.client.hocon_validator_cli <file> [flags]`.

Exit codes: `0` pass · `1` validation errors · `2` file not found, parse error, or bad
registry dir.

### What it checks

- `tools` is a list of strings/dicts; `args.tools` is a dict or list
- `function.description` and `instructions` are non-empty strings when present
- referenced agents exist (missing nodes)
- no unreachable nodes; exactly one front man
- tool names match `^[a-zA-Z0-9_-]+$`
- `parameters` parse through the real Pydantic conversion pipeline, and every name in
  `required` exists in `properties` (recursing into nested objects and array items)
- external-agent refs and MCP URLs appear in the lists you supplied

### What it deliberately does not check

- **Cycles** — they are legal in neuro-san
- **Toolbox names** — no toolbox validator exists yet
- Anything semantic: prompt quality, whether the model can actually do the task

`--json-output` exists in the arg parser but is **dead code** — it is never read.

### Registry directory resolution

Needed so `include` statements resolve. Order: `--registry-dir` flag → parent-of-parent of
`AGENT_MANIFEST_FILE` → current working directory.

Implementation detail worth knowing when debugging: the validator **copies your file to
`<registry_dir>/_temp_validate_<basename>`**, parses it there, and deletes it in a `finally`.
That is why includes resolve as if the file lived at the registry root.

---

## Environment variables

### Core

| Variable | Default | Purpose |
|---|---|---|
| `AGENT_MANIFEST_FILE` | `<cwd>/registries/manifest.hocon` | Root manifest |
| `AGENT_TOOL_PATH` | `<cwd>/coded_tools` | Coded tool root |
| `AGENT_TOOL_PATH_ONLY` | `false` | Restrict class resolution to `AGENT_TOOL_PATH` |
| `AGENT_TOOLBOX_INFO_FILE` | packaged `neuro_san_studio/toolbox/toolbox_info.hocon` | Toolbox config; `""` opts out |
| `AGENT_NETWORK_DESIGNER_TOOLBOX_INFO_FILE` | packaged designer palette | Designer's tool palette |
| `MCP_SERVERS_INFO_FILE` | `<cwd>/mcp/mcp_info.hocon` if present, else packaged | MCP server config |
| `AGENT_LLM_INFO_FILE` | none | Extra LLM catalog |
| `AGENT_MANIFEST_UPDATE_PERIOD_SECONDS` | `5` | Manifest hot-reload interval |
| `AGENT_MCP_ENABLE` / `AGENT_MCP_ONLY` | off | Serve networks as MCP tools |

### Server and UI

| Variable | Default |
|---|---|
| `NEURO_SAN_SERVER_HOST` | `localhost` |
| `NEURO_SAN_SERVER_HTTP_PORT` | `8080` |
| `NEURO_SAN_SERVER_CONNECTION` | `http` |
| `NSFLOW_HOST` | `localhost` |
| `NSFLOW_PORT` | `4173` |
| `NSFLOW_PLUGIN_CRUSE` | `true` |
| `NSFLOW_CLIENT_ONLY` | set by `--client-only` |
| `LOG_LEVEL` | `info` |
| `THINKING_FILE` | `<cwd>/logs/agent_thinking.txt` |
| `THINKING_DIR` | `<cwd>/logs/thinking_dir` |

### LLM providers

`OPENAI_API_KEY` · `ANTHROPIC_API_KEY` · `GOOGLE_API_KEY` · `AZURE_OPENAI_API_KEY` +
`AZURE_OPENAI_ENDPOINT` + `OPENAI_API_VERSION` + `AZURE_OPENAI_DEPLOYMENT_NAME` ·
`AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` · `MISTRAL_API_KEY`

Validate them with `ns check-llm-keys --tier {1,2,3}` (1 = placeholder check, 2 = format,
3 = live API call, the default).

### Agent Network Designer

| Variable | Default |
|---|---|
| `AGENT_NETWORK_DESIGNER_MANIFEST_FILE` | `registries/manifest_and.hocon` |
| `AGENT_NETWORK_DESIGNER_SUBDIRECTORY` | `generated` |
| `AGENT_NETWORK_DESIGNER_DEMO_MODE` | `true` |
| `AGENT_NETWORK_DESIGNER_USE_RESERVATIONS` | `false` |
| `AGENT_NETWORK_DESIGNER_MAX_VALIDATION_ATTEMPTS` | `3` |
| `AGENT_NETWORK_DESIGNER_VERBOSE` | unset |

### Observability

Langfuse is built into neuro-san — no plugin needed: `LANGFUSE_ENABLED=true` plus
`LANGFUSE_SECRET_KEY`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_HOST` (install the
`neuro-san-studio[langfuse]` extra; `ns run` errors out if enabled but not installed).

LangSmith works out of the box with `LANGSMITH_TRACING=true` and `LANGSMITH_API_KEY`.

Arize Phoenix runs as a plugin via `config/plugins.hocon` and `PHOENIX_ENABLED`, with
`PHOENIX_HOST` (`127.0.0.1`), `PHOENIX_PORT` (`6006`), `PHOENIX_PROJECT_NAME`,
`PHOENIX_AUTOSTART`, and the standard `OTEL_*` variables.

`allow.to_tracing.sly_data` is what gates sly_data values reaching any of these — by default
keys appear with `<redacted>` values.

---

## Quick start

```bash
mkdir my_project && cd my_project
uv init && uv venv && source .venv/bin/activate
uv add neuro-san-studio
ns init
export OPENAI_API_KEY="sk-..."
ns check-llm-keys
ns check-config
ns run
```

Python **≥3.12** is required.

---

## Agent Network Designer

In the nsflow UI: **NEW** → Agent Network Designer → describe the network → it writes to
`registries/generated/` → **Launch**.

Supporting networks, served with `{"serve": true, "public": false}`:
`agent_network_editor`, `agent_network_instructions_editor`, `agent_network_query_generator`.
Also available: `agent_network_architect`, `agent_network_test_generator`.

Generated files carry a `metadata.date_created` timestamp. Older generated files may still
contain stale header comments referencing `python -m run` and `aaosa_command` — ignore those.
