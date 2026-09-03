---
name: neuro-san-agent-network
description: Create, design, and debug agent networks for the neuro-san framework. Use this skill when building HOCON agent network files, wiring up coded tools, configuring LLM providers, setting up AAOSA protocols, handling sly_data, or registering networks in manifests. Covers all neuro-san agent network authoring tasks.
when_to_use: When asked to create a neuro-san agent, write a HOCON file, add a coded tool, configure an agent network, set up multi-agent communication, register a new network, or explain any part of the neuro-san framework.
argument-hint: [network-name] [description]
allowed-tools: Read Bash
---

# Neuro-SAN Agent Network Skill

You are an expert in the neuro-san framework. Use this complete reference to create, edit, and debug HOCON-based agent networks.

---

## 1. WHAT IS NEURO-SAN?

**Neuro AI System of Agent Networks (Neuro SAN)** is a declarative multi-agent orchestration framework. Agent networks are defined entirely in **HOCON files** — no imperative code required (unless adding custom Python coded tools).

Core concepts:
- **Agent network** — a set of cooperating LLM agents defined in one `.hocon` file
- **Front man** — the single entry-point agent (first in the `tools` array)
- **Tool nodes** — internal agents that handle sub-tasks
- **Coded tools** — Python classes that implement non-LLM functionality
- **External agents** — references to other agent networks (local or remote)

---

## 2. HOCON FILE STRUCTURE

Every `.hocon` file follows this skeleton:

```hocon
{
    # Optional: metadata for discovery and testing
    "metadata": {
        "description": "Short description of what this network does.",
        "tags": ["tag1", "tag2"],
        "sample_queries": ["Example question 1", "Example question 2"]
    },

    # Optional: include shared config files
    include "registries/aaosa_basic.hocon"

    # Optional: network-level LLM config (applies to all agents unless overridden)
    "llm_config": {
        "model_name": "gpt-4o",
        "temperature": 0.7
    },

    # Required: array of agent definitions
    "tools": [
        { /* front man — MUST be first */ },
        { /* agent 2 */ },
        { /* agent 3 */ },
        ...
    ]
}
```

### HOCON syntax rules
- Use `include "path/to/file.hocon"` to pull in shared templates
- Use `${variable_name}` for substitution (defined at network level)
- Use `${?ENV_VAR}` for optional environment variable substitution
- Commas between object fields are optional; trailing commas are allowed

---

## 3. AGENT DEFINITION SCHEMA

Each agent object in the `tools` array:

```hocon
{
    # ---- REQUIRED ----
    "name": "AgentName",                    # Unique within the network, PascalCase by convention
    "function": {
        "description": "What this agent does and when to call it.",
        # parameters block is REQUIRED for all agents except the front man
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "The question or task to handle."
                }
            },
            "required": ["query"]
        }
    },
    "instructions": "Detailed LLM system prompt for this agent.",

    # ---- OPTIONAL ----
    "command": "Additional execution instructions (used in AAOSA for response format).",
    "tools": ["OtherAgent", "/external_network", "http://host:port/network"],
    "llm_config": { "model_name": "claude-sonnet-4-6" },  # Agent-level override
    "class": "module.path.ClassName",        # For coded tools (Python)
    "toolbox": "tavily_search",              # For prebuilt toolbox tools
    "args": { "key": "value" },              # Extra args passed to coded tool / toolbox
    "middleware": [ { "class": "...", "args": {} } ],
    "allow": {
        "to_downstream":   { "sly_data": ["key1"] },
        "from_downstream": { "sly_data": ["key2"] },
        "to_upstream":     { "sly_data": ["key3"] }
    },
    "max_steps": 50,
    "max_execution_seconds": 120,
    "structure_formats": "json"
}
```

### Front man rules
- MUST be the **first** agent in the `tools` array
- MUST NOT have `"class"` or `"toolbox"` fields
- MUST NOT have `"parameters"` inside `"function"` (it's the user entry-point)
- Should list all child agents it can delegate to in its `"tools"` array

---

## 4. PARAMETER TYPES

The `function.parameters` block follows JSON Schema. The top-level `type` must always be `"object"`.

```hocon
"parameters": {
    "type": "object",
    "properties": {
        "text":       { "type": "string",  "description": "..." },
        "count":      { "type": "integer", "description": "..." },
        "ratio":      { "type": "number",  "description": "..." },
        "enabled":    { "type": "boolean", "description": "..." },
        "tags": {
            "type": "array",
            "items": { "type": "string" },
            "description": "..."
        },
        "options": {
            "type": "object",
            "properties": {
                "mode": { "type": "string" }
            }
        }
    },
    "required": ["text"]
}
```

---

## 5. LLM CONFIGURATION

### Network-level (default for all agents)
```hocon
"llm_config": {
    "model_name": "gpt-4o",
    "temperature": 0.7,
    "max_tokens": 2048
}
```

### Agent-level override
Place inside the agent object to override for that agent only.

### Supported providers and model names

| Provider     | Example model_name values |
|--------------|---------------------------|
| OpenAI       | `gpt-4o`, `gpt-4-turbo`, `o3`, `o4-mini` |
| Anthropic    | `claude-sonnet-4-6`, `claude-opus-4-7`, `claude-haiku-4-5` |
| Azure OpenAI | `azure-gpt-4o` (requires `AZURE_OPENAI_API_KEY` + `AZURE_OPENAI_ENDPOINT`) |
| Bedrock      | `bedrock-us-claude-3-7-sonnet` (requires AWS credentials) |
| Gemini       | `gemini-2.5-pro`, `gemini-2-flash` |
| Ollama       | `llama3.1`, `qwen3:8b` (local; set `base_url`) |

### Reasoning / thinking models
```hocon
# OpenAI
"llm_config": { "model_name": "o3", "reasoning_effort": "high" }

# Anthropic
"llm_config": {
    "model_name": "claude-opus-4-7",
    "thinking": { "type": "enabled", "budget_tokens": 10000 }
}

# Gemini
"llm_config": { "model_name": "gemini-2.5-pro", "thinking_level": "medium" }
```

### Fallbacks
```hocon
"llm_config": {
    "fallbacks": [
        { "model_name": "gpt-4o" },
        { "model_name": "claude-sonnet-4-6" }
    ]
}
```

---

## 6. AAOSA PROTOCOL

AAOSA (Adaptive Agent Oriented Software Architecture) is the standard multi-agent coordination protocol in neuro-san. It lets agents autonomously discover which sub-agents are relevant for an inquiry without hard-coded routing logic.

### When to use AAOSA

Use AAOSA when:
- You have **3 or more sub-agents** with overlapping or ambiguous responsibilities
- The user's inquiry could be handled by **different agents depending on context** (e.g. time of day, phrasing, domain)
- You want agents to **self-declare relevance** rather than the front man deciding up-front
- Sub-agents can each handle **part of** a compound inquiry (partial claim pattern)

Do NOT use AAOSA when:
- You have only 1-2 clearly distinct tools — just call them directly
- Routing is deterministic and non-overlapping — explicit tool descriptions are enough
- You need very low latency — AAOSA adds a Determine round-trip before Fulfill

### How it works

```
User → FrontMan
         ├─→ AgentA (mode: Determine) → {Relevant: Yes, Strength: 8, Claim: All}
         ├─→ AgentB (mode: Determine) → {Relevant: Yes, Strength: 5, Claim: Partial}
         └─→ AgentC (mode: Determine) → {Relevant: No, Strength: 1, Claim: None}

FrontMan picks AgentA (strongest claim) and optionally AgentB (partial claim):
         ├─→ AgentA (mode: Fulfill) → final response
         └─→ AgentB (mode: Follow up) → partial response

FrontMan compiles → User
```

Three call modes:
- **`Determine`** — "Can you handle this, and how confident are you?"
- **`Fulfill`** — "Handle it."
- **`Follow up`** — "Here is additional info you said you needed."

### The three AAOSA variants

There are three template files in `registries/`, each defining `${aaosa_instructions}`, `${aaosa_call}`, and `${aaosa_command}`:

---

#### Variant 1: `aaosa_basic.hocon` — recommended default

Response format uses a simple `[AAOSA]` text block. Simpler, cheaper, works well with most models.

```
[AAOSA]
Name: <your name>
Inquiry: <the inquiry>
Mode: <Determine | Follow up | Fulfill>
Relevant: <Yes | No>
Strength: <1–10>
Claim: <All | Partial | None>
Requirements: <None | list>
Response: <your response>
```

**Instructions summary:** Call all down-chain agents. Analyze responses. Follow up, clarify, delegate to the most relevant agent(s), then compile.

**Use when:** Starting a new network, general-purpose routing, cost-sensitive deployments.

```hocon
include "registries/aaosa_basic.hocon"
```

---

#### Variant 2: `aaosa.hocon` — strict JSON response

Response format uses a JSON block. More structured and parseable, better for complex coordination where the parent agent needs to process sub-agent responses programmatically.

**Determine mode response:**
```json
{
    "Name": "<agent name>",
    "Inquiry": "<the inquiry>",
    "Mode": "Determine",
    "Relevant": "Yes | No",
    "Strength": 8,
    "Claim": "All | Partial | None",
    "Requirements": "None | list of requirements"
}
```

**Fulfill / Follow up mode response:**
```json
{
    "Name": "<agent name>",
    "Inquiry": "<the inquiry>",
    "Mode": "Fulfill",
    "Response": "<your response>"
}
```

**Instructions summary:** Same routing logic as basic, but returns strictly structured JSON in `command`.

**Use when:** You need machine-readable sub-agent responses, building on top of AAOSA output programmatically, or the front man needs to interpret structured claims.

```hocon
include "registries/aaosa.hocon"
```

---

#### Variant 3: `aaosa_basic_debug.hocon` — development/debugging

Extends `aaosa_basic.hocon`. Appends `[DEBUG]` instructions to `aaosa_instructions`, asking agents to report errors, exceptions, ambiguities, and prompt improvement suggestions.

```hocon
include "registries/aaosa_basic_debug.hocon"
```

**Use when:** Developing and debugging a new network. Switch back to `aaosa_basic.hocon` before production.

---

#### Variant 4: Custom inline AAOSA instructions

Override `aaosa_instructions` directly in your network file to tailor routing behavior to your domain. The custom value replaces the shared one for that network only.

```hocon
{
    include "config/llm_config.hocon"

    "aaosa_instructions": """
When you receive an inquiry:
0. If clearly not relevant, say so immediately.
1. Always call your tools to determine which down-chain agents are responsible.
2. Ask those agents what they need to handle their part.
3. Delegate with the fulfilled requirements.
4. Compile and return the final response.
"""
    # ... tools ...
}
```

**Use when:** The default instructions don't fit your network's routing logic, you need domain-specific routing rules, or you want more concise instructions to reduce token costs.

---

### HOCON wiring — roles of each substitution variable

| Variable | Used on | Purpose |
|---|---|---|
| `${aaosa_instructions}` | **All agents** — appended to `"instructions"` | Tells the LLM how to route via AAOSA |
| `${aaosa_call}` | **Sub-agents only** — assigned to `"function"` | Defines `inquiry` + `mode` parameters |
| `${aaosa_command}` | **Sub-agents only** — assigned to `"command"` | Tells the LLM what response format to return |

The **front man** gets `${aaosa_instructions}` in its `instructions` but does **not** use `${aaosa_call}` or `${aaosa_command}` — it takes free-form user input.

### Standard AAOSA wiring pattern

```hocon
{
    include "registries/aaosa_basic.hocon"
    include "config/llm_config.hocon"

    "instructions_prefix": """
You are part of a [domain] assistant network.
Only answer inquiries within your area of expertise.
Do not mention what you cannot do.
""",

    "tools": [
        {
            # Front man — no aaosa_call, no aaosa_command
            "name": "MainAssistant",
            "function": { "description": "Handles user inquiries about [domain]." },
            "instructions": ${instructions_prefix} """
Your name is MainAssistant. Coordinate with your specialists.
""" ${aaosa_instructions},
            "tools": ["SpecialistA", "SpecialistB", "SpecialistC"]
        },
        {
            # Sub-agent — uses aaosa_call and aaosa_command
            "name": "SpecialistA",
            "function": ${aaosa_call},
            "instructions": ${instructions_prefix} """
Your name is SpecialistA. You handle [sub-domain A].
""" ${aaosa_instructions},
            "command": ${aaosa_command}
        },
        {
            "name": "SpecialistB",
            "function": ${aaosa_call},
            "instructions": ${instructions_prefix} """
Your name is SpecialistB. You handle [sub-domain B].
""" ${aaosa_instructions},
            "command": ${aaosa_command},
            "tools": ["LeafToolB"]   # sub-agents can have their own tools
        },
        {
            "name": "SpecialistC",
            "function": ${aaosa_call},
            "instructions": ${instructions_prefix} """
Your name is SpecialistC. You handle [sub-domain C]. You cannot do anything else.
""" ${aaosa_instructions},
            "command": ${aaosa_command}
        },
        {
            # Leaf coded tool — NOT an AAOSA agent, no aaosa fields
            "name": "LeafToolB",
            "function": {
                "description": "Looks up data for SpecialistB.",
                "parameters": {
                    "type": "object",
                    "properties": { "query": { "type": "string" } },
                    "required": ["query"]
                }
            },
            "class": "my_module.LeafTool"
        }
    ]
}
```

### Generated network front man pattern

In networks generated by the Agent Network Designer, the front man merges `${aaosa_call}` with a description override using HOCON merge syntax. This makes the front man also a formal AAOSA participant (it can receive `Determine`/`Fulfill` calls from a parent network):

```hocon
{
    "name": "network_lead",
    "function": ${aaosa_call} {
        "description": "An assistant that answers inquiries from the user."
    },
    "instructions": ${instructions_prefix} """
Never express irrelevance unless you have first consulted all your tools.
""" ${aaosa_instructions},
    "tools": ["SubAgentA", "SubAgentB"]
}
```

The `${aaosa_call}` provides the `inquiry`/`mode` parameter structure; the inline `{ "description": "..." }` overrides just the description. Use this pattern when the network itself will be embedded inside a larger AAOSA hierarchy as an external agent.

### AAOSA pitfalls

| Mistake | Fix |
|---|---|
| Front man has `${aaosa_call}` as its function | Front man should have a plain `"function": { "description": "..." }` unless it's an embedded sub-network |
| Front man has `${aaosa_command}` in `"command"` | Remove it — only sub-agents return AAOSA response blocks |
| Sub-agent missing `${aaosa_command}` | The LLM won't know what format to return; add `"command": ${aaosa_command}` |
| `${aaosa_instructions}` not appended to sub-agent instructions | Sub-agent won't know how to respond to Determine/Fulfill calls |
| Using `aaosa.hocon` and `aaosa_basic.hocon` in the same network | Pick one — they define the same variable names and will conflict |
| Custom `aaosa_instructions` doesn't mention Determine/Fulfill/Follow up modes | Sub-agents won't understand the mode parameter; always reference the three modes |

---

## 7. CODED TOOLS (Python)

For non-LLM logic: database queries, API calls, computations, etc.

### File location
- `coded_tools/{network_name}/my_tool.py` — scoped to one network
- `coded_tools/my_tool.py` — shared across all networks

### Python interface
```python
from neuro_san.interfaces.coded_tool import CodedTool
from typing import Any, Dict, Union

class MyTool(CodedTool):
    async def async_invoke(
        self, args: Dict[str, Any], sly_data: Dict[str, Any]
    ) -> Union[Dict[str, Any], str]:
        # args: dict of LLM-provided values + HOCON-specified "args"
        # sly_data: sensitive data invisible to LLM
        param = args.get("param")
        secret = sly_data.get("api_key")
        result = do_work(param, secret)
        return {"result": result}   # or return a plain string
```

Implement `async_invoke` (preferred) or synchronous `invoke` as fallback.

### HOCON reference
```hocon
{
    "name": "MyTool",
    "function": {
        "description": "Does something specific.",
        "parameters": {
            "type": "object",
            "properties": {
                "param": { "type": "string", "description": "Input value." }
            },
            "required": ["param"]
        }
    },
    "class": "my_module.MyTool",      # Python import path relative to AGENT_TOOL_PATH
    "args": { "static_arg": "value" } # Merged into args dict at call time
}
```

Set `AGENT_TOOL_PATH` env var to the root `coded_tools/` directory.

---

## 8. TOOLBOX (PREBUILT TOOLS)

The toolbox is a catalog of pre-configured tools (LangChain tools, toolkits, and shared coded tools) that any agent network can use by name — no Python code required. Two layers exist:

- **Default toolbox** — built into the core neuro-san library (`neuro_san/internals/run_context/langchain/toolbox/toolbox_info.hocon`). Always available.
- **Studio toolbox** — defined in `toolbox/toolbox_info.hocon` in the repo root. Loaded when `AGENT_TOOLBOX_INFO_FILE` points to it (the default).

### How to use a toolbox tool in HOCON

```hocon
{
    "name": "WebSearch",
    "toolbox": "tavily_search"
    # No "function", "instructions", or "class" needed — all defined in the toolbox config
}
```

Override constructor args per-agent using the `"args"` field:

```hocon
{
    "name": "WebSearch",
    "toolbox": "tavily_search",
    "args": {
        "max_results": 10,
        "search_depth": "advanced",
        "time_range": "week"
    }
}
```

HOCON `args` values are **merged on top of** the toolbox defaults — only the keys you specify are overridden.

### Toolkits (multi-tool entries)

Some toolbox entries are **toolkits** that register multiple tools at once (e.g. `requests_toolkit` gives GET + POST + PATCH + PUT + DELETE). Reference a toolkit by its name — the framework calls `.get_tools()` internally.

```hocon
{ "name": "HttpClient", "toolbox": "requests_toolkit" }
```

### Default toolbox tools (always available, no extra config)

| Tool name | What it does | API key required |
|---|---|---|
| `requests_get` | HTTP GET | no |
| `requests_post` | HTTP POST | no |
| `requests_patch` | HTTP PATCH | no |
| `requests_put` | HTTP PUT | no |
| `requests_delete` | HTTP DELETE | no |
| `requests_toolkit` | All HTTP verbs as one toolkit | no |
| `get_current_date_time` | Current date/time, UTC offset or IANA tz | no |

### Studio toolbox tools (`toolbox/toolbox_info.hocon`)

**Web search**

| Tool name | What it does | Requires |
|---|---|---|
| `ddgs_search` | DuckDuckGo web search | nothing (no key) |
| `brave_search` | Brave web search | `BRAVE_API_KEY` |
| `google_search` | Google Custom Search | `GOOGLE_SEARCH_API_KEY`, `GOOGLE_SEARCH_CSE_ID` |
| `google_serper` | Google via Serper API (news/images/places) | `SERPER_API_KEY` |
| `tavily_search` | AI-optimized search | `TAVILY_API_KEY` + `pip install langchain-tavily` |
| `anthropic_search` | Web search via Anthropic | `ANTHROPIC_API_KEY` + `langchain-anthropic>=0.3.13` |
| `openai_search` | Web search via OpenAI | `OPENAI_API_KEY` + `langchain-openai>=0.3.26` |

**Web fetching**

| Tool name | What it does | Requires |
|---|---|---|
| `web_fetch` | Fetch a URL, returns plain-text + metadata. Supports HTML and PDF. | `pip install beautifulsoup4 aiohttp pypdf` |

**Code execution**

| Tool name | What it does | Requires |
|---|---|---|
| `openai_code_interpreter` | Execute Python via OpenAI code interpreter | `OPENAI_API_KEY`, `langchain-openai>=0.3.26` |
| `openai_image_generation` | Generate images via OpenAI | `OPENAI_API_KEY` |
| `openai_video_generation` | Generate video via OpenAI | `OPENAI_API_KEY` |
| `anthropic_code_execution` | Execute Python via Anthropic | `ANTHROPIC_API_KEY`, `langchain-anthropic>=0.3.13` |
| `gemini_image_generation` | Generate images via Gemini | `GOOGLE_API_KEY`, `pip install google-genai` |

**RAG (Retrieval-Augmented Generation)**

| Tool name | What it does | Requires |
|---|---|---|
| `pdf_rag` | RAG over PDF files | `pip install pymupdf>=1.25.5` |
| `webpage_rag` | RAG over web pages | — |
| `docling_rag` | RAG over multi-format docs (Word, PPTX, etc.) | `pip install langchain-docling` |
| `wikipedia_rag` | RAG over Wikipedia | `pip install wikipedia` |
| `arxiv_retriever` | Search and RAG over arXiv papers | `pip install arxiv` (+ `pymupdf` for full text) |
| `confluence_rag` | RAG over Confluence pages | `JIRA_USERNAME`, `JIRA_API_TOKEN`, `pip install atlassian-python-api` |
| `wikimedia_media_search` | Find images/audio/video on Wikimedia Commons | — |

**Email**

| Tool name | What it does | Requires |
|---|---|---|
| `gmail_toolkit` | Read/search/compose Gmail | `pip install langchain-google-community[gmail]` + `credentials.json` |
| `send_gmail_message_with_attachment` | Send email with file attachment | same as above |

**Project management**

| Tool name | What it does | Requires |
|---|---|---|
| `jira_toolkit` | Jira: search issues, create tickets, manage projects | `JIRA_USERNAME`, `JIRA_API_TOKEN`, `JIRA_INSTANCE_URL`, `JIRA_CLOUD`, `pip install atlassian-python-api` |

**Agent orchestration**

| Tool name | What it does | Requires |
|---|---|---|
| `call_agent` | Call another agent network by name | — |
| `agent_network_html_generator` | Generate HTML visualization of a network | `pip install pyvis` |

### Complete wiring example (multiple toolbox tools)

```hocon
{
    include "config/llm_config.hocon"

    "tools": [
        {
            "name": "ResearchAssistant",
            "function": { "description": "Helps research topics using web search and document retrieval." },
            "instructions": "You are a research assistant. Use your tools to find and summarize information.",
            "tools": ["WebSearch", "FetchPage", "ArxivSearch", "DateTime"]
        },
        {
            "name": "WebSearch",
            "toolbox": "ddgs_search"   # no API key needed
        },
        {
            "name": "FetchPage",
            "toolbox": "web_fetch",
            "args": { "max_content_chars": 10000 }
        },
        {
            "name": "ArxivSearch",
            "toolbox": "arxiv_retriever",
            "args": { "top_k_results": 5 }
        },
        {
            "name": "DateTime",
            "toolbox": "get_current_date_time"
        }
    ]
}
```

### Adding a new tool to the toolbox

To register a new coded tool or LangChain tool so any network can use it by name, add an entry to `toolbox/toolbox_info.hocon`:

```hocon
# In toolbox/toolbox_info.hocon

"my_custom_tool": {
    "class": "coded_tools.tools.my_module.MyTool",   # or a LangChain class
    "description": "What this tool does.",
    "parameters": {
        "type": "object",
        "properties": {
            "query": { "type": "string", "description": "Input query." }
        },
        "required": ["query"]
    },
    "args": {
        "default_param": "value"   # default constructor args
    },
    "base_tool_info_url": "https://docs.example.com/my-tool"   # optional
}
```

Then use it in any network:

```hocon
{ "name": "MyAgent", "toolbox": "my_custom_tool" }
```

For LangChain toolkits (classes with `.get_tools()`), define the same way — the framework detects toolkit classes and calls `.get_tools()` automatically.

---

## 9. EXTERNAL AGENT NETWORKS

Reference another agent network as a tool — same protocol as internal agents.

```hocon
# Local (same server) — use a leading slash
"tools": ["/other_network_name"]

# Remote (different server)
"tools": ["http://192.168.1.100:8080/other_network_name"]
```

---

## 10. MCP SERVERS

Expose all tools from an MCP server, or whitelist specific ones:

```hocon
# All tools
"tools": ["https://mcp.example.com/server"]

# Filtered
"tools": [
    {
        "url": "https://mcp.example.com/server",
        "tools": ["search", "summarize"]
    }
]
```

Pass auth headers via `sly_data["http_headers"]` (see §11).

---

## 11. SLY_DATA — SECURE SENSITIVE DATA

`sly_data` is a side-channel dict that flows through the agent network without ever appearing in LLM prompts. Use it for API keys, user tokens, PII, etc.

### Boundaries
```hocon
"allow": {
    "to_downstream":   { "sly_data": ["api_key", "user_id"] },   # sent to child networks
    "from_downstream": { "sly_data": ["child_result"] },          # received from child networks
    "to_upstream":     { "sly_data": ["output_token"] }           # sent back to caller / client
}
```

### Access in coded tools
```python
async def async_invoke(self, args, sly_data):
    token = sly_data.get("api_key")
    sly_data["computed_value"] = result   # write back
```

### Inject from client
Pass `sly_data` as a dict in the initial request payload.

---

## 12. MIDDLEWARE

Hooks that execute around agent and LLM calls.

```hocon
"middleware": [
    {
        "class": "path.to.MiddlewareClass",
        "args": {
            "option1": "value1"
        }
    }
]
```

Available hook methods to override in your class:
- `abefore_agent(chat_messages, sly_data)` — before agent starts
- `aafter_agent(chat_messages, sly_data)` — after agent finishes
- `abefore_model(messages, sly_data)` — before LLM call
- `aafter_model(response, sly_data)` — after LLM call
- `awrap_model_call(call_fn, messages, sly_data)` — intercept/replace LLM call
- `awrap_tool_call(call_fn, tool_name, args, sly_data)` — intercept tool call

Auto-populated args (inject as constructor params): `sly_data`, `origin`, `origin_str`, `chat_history`, `journal`, `progress_reporter`.

---

## 13. REGISTERING NETWORKS IN MANIFESTS

### Directory layout
```
registries/
├── manifest.hocon              # Root manifest
├── aaosa.hocon                 # Full AAOSA template
├── aaosa_basic.hocon           # Simplified AAOSA
├── config/
│   └── llm_config.hocon        # Shared LLM config
├── basic/
│   ├── manifest.hocon
│   └── my_network.hocon
└── my_category/
    ├── manifest.hocon
    └── my_network.hocon
```

### Root manifest
```hocon
{
    include "registries/basic/manifest.hocon"
    include "registries/my_category/manifest.hocon"
}
```

### Category manifest
```hocon
{
    "my_network": true,          # enabled
    "another_network": false     # disabled (not served)
}
```

The key must match the `.hocon` filename (without extension) in that directory.

### Environment variables
```bash
export AGENT_MANIFEST_FILE="./registries/manifest.hocon"
export AGENT_TOOL_PATH="./coded_tools"
export OPENAI_API_KEY="sk-..."        # or ANTHROPIC_API_KEY, etc.
```

---

## 14. COMPLETE EXAMPLES

### Minimal single-agent network
```hocon
{
    "llm_config": { "model_name": "gpt-4o" },
    "tools": [
        {
            "name": "Assistant",
            "function": { "description": "A helpful assistant." },
            "instructions": "You are a helpful assistant. Answer the user's questions clearly."
        }
    ]
}
```

### Hierarchical multi-agent network
```hocon
{
    "metadata": {
        "description": "Customer support router.",
        "sample_queries": ["I need help with my order.", "How do I reset my password?"]
    },
    "llm_config": { "model_name": "gpt-4o", "temperature": 0.3 },
    "tools": [
        {
            "name": "SupportRouter",
            "function": { "description": "Routes customer inquiries to the right specialist." },
            "instructions": "You are a customer support coordinator. Greet the customer and route their issue to the correct specialist: OrdersExpert for order issues, AccountExpert for account/password issues.",
            "tools": ["OrdersExpert", "AccountExpert"]
        },
        {
            "name": "OrdersExpert",
            "function": {
                "description": "Handles order-related questions: tracking, returns, shipping.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "inquiry": { "type": "string", "description": "The order-related question." }
                    },
                    "required": ["inquiry"]
                }
            },
            "instructions": "You are an orders specialist. Help customers with order tracking, returns, and shipping questions.",
            "tools": ["OrdersDB"]
        },
        {
            "name": "AccountExpert",
            "function": {
                "description": "Handles account issues: passwords, billing, profile.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "inquiry": { "type": "string", "description": "The account-related question." }
                    },
                    "required": ["inquiry"]
                }
            },
            "instructions": "You are an account specialist. Help customers reset passwords, manage billing, and update profiles."
        },
        {
            "name": "OrdersDB",
            "function": {
                "description": "Look up order status by order ID.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "order_id": { "type": "string", "description": "The order ID to look up." }
                    },
                    "required": ["order_id"]
                }
            },
            "class": "support_tools.order_lookup.OrderLookup"
        }
    ]
}
```

### AAOSA network with sly_data
```hocon
{
    include "registries/aaosa_basic.hocon"

    "llm_config": { "model_name": "gpt-4o" },

    "tools": [
        {
            "name": "ResearchCoordinator",
            "function": { "description": "Coordinates research tasks across specialists." },
            "instructions": "You coordinate research. " ${aaosa_instructions},
            "tools": ["WebResearcher", "DataAnalyst"],
            "allow": {
                "to_downstream": { "sly_data": ["tavily_api_key"] }
            }
        },
        {
            "name": "WebResearcher",
            "function": ${aaosa_call},
            "instructions": "You search the web for information. " ${aaosa_instructions},
            "command": ${aaosa_command},
            "tools": ["WebSearch"]
        },
        {
            "name": "DataAnalyst",
            "function": ${aaosa_call},
            "instructions": "You analyze data and produce summaries. " ${aaosa_instructions},
            "command": ${aaosa_command}
        },
        {
            "name": "WebSearch",
            "toolbox": "tavily_search",
            "args": { "max_results": 5 }
        }
    ]
}
```

---

## 15. INSTRUCTIONS WRITING BEST PRACTICES

1. **Put critical rules at the top AND bottom** — avoids "lost in the middle" problem
2. **Use ALL CAPS for absolute rules** — `NEVER reveal internal tool names`, `ALWAYS respond in JSON`
3. **Number steps** for multi-step processes
4. **Be explicit about format** — if the agent must return JSON, describe the exact schema
5. **Use AAOSA instructions** for agents that delegate: append `${aaosa_instructions}` after your own text
6. **Keep front man instructions high-level** — let specialists handle domain specifics
7. **Reference sly_data keys by name** — tell agents what secrets are available without embedding values

---

## 16. COMMON PITFALLS

| Mistake | Fix |
|---------|-----|
| Front man has `parameters` in `function` | Remove `parameters` — front man takes free-form user input |
| Front man has `class` field | Remove it — front man must be LLM-driven |
| Non-front-man agent missing `parameters` | Add `parameters` so the calling agent knows how to invoke it |
| Coding path for `class` wrong | Path is relative to `AGENT_TOOL_PATH`; use dot-notation e.g. `subdir.module.Class` |
| Network not showing in UI | Check it's set to `true` in the category `manifest.hocon` |
| Secrets visible in LLM prompts | Move to `sly_data`; configure `allow` boundaries |
| AAOSA agents not responding correctly | Ensure both `${aaosa_instructions}` in `instructions` and `${aaosa_command}` in `command` |
| `include` path wrong | Paths in `include` are relative to the project root, not the HOCON file |

---

## 17. FILE NAMING AND PLACEMENT CHECKLIST

- [ ] HOCON file in `registries/<category>/my_network.hocon`
- [ ] Network key added to `registries/<category>/manifest.hocon` set to `true`
- [ ] Validated with `python -m neuro_san.client.hocon_validator_cli registries/<category>/my_network.hocon --verbose`
- [ ] Category manifest included in root `registries/manifest.hocon`
- [ ] Coded tools in `coded_tools/<network_name>/` or `coded_tools/` (shared)
- [ ] `AGENT_MANIFEST_FILE` and `AGENT_TOOL_PATH` env vars set before starting server
- [ ] Required LLM provider API key exported

---

## 18. ENVIRONMENT VARIABLES

### Core framework (required for any network to run)

| Variable | Default | Purpose |
|---|---|---|
| `AGENT_MANIFEST_FILE` | `registries/manifest.hocon` | Path to the root manifest HOCON file |
| `AGENT_TOOL_PATH` | `coded_tools/` | Root directory for Python coded tools |
| `AGENT_TOOLBOX_INFO_FILE` | `toolbox/toolbox_info.hocon` | Toolbox configuration file |
| `MCP_SERVERS_INFO_FILE` | `mcp/mcp_info.hocon` | MCP servers configuration file |

### LLM provider keys (set at least one)

| Variable | Provider |
|---|---|
| `OPENAI_API_KEY` | OpenAI (`gpt-4o`, `o3`, etc.) |
| `ANTHROPIC_API_KEY` | Anthropic (`claude-sonnet-4-6`, `claude-opus-4-7`, etc.) |
| `GOOGLE_API_KEY` | Google Gemini (`gemini-2.5-pro`, `gemini-2-flash`, etc.) |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI endpoint URL |
| `OPENAI_API_VERSION` | Azure OpenAI API version |
| `AZURE_OPENAI_DEPLOYMENT_NAME` | Azure deployment name |
| `AWS_ACCESS_KEY_ID` | AWS Bedrock |
| `AWS_SECRET_ACCESS_KEY` | AWS Bedrock |

### Server and UI

| Variable | Default | Purpose |
|---|---|---|
| `NEURO_SAN_SERVER_HOST` | `localhost` | Agent server hostname |
| `NEURO_SAN_SERVER_HTTP_PORT` | `8080` | Agent server HTTP port |
| `AGENT_HTTP_PORT` | `8001` | Internal agent service port |
| `NSFLOW_HOST` | `localhost` | NSFlow UI hostname |
| `NSFLOW_PORT` | `4173` | NSFlow UI port (access at `http://localhost:4173/`) |
| `LOG_LEVEL` | `info` | Log level: `debug`, `info`, `warn`, `error` |
| `AGENT_MAX_CONCURRENT_REQUESTS` | `100` | Concurrent request limit |

### Manifest and tool discovery

| Variable | Default | Purpose |
|---|---|---|
| `AGENT_MANIFEST_UPDATE_PERIOD_SECONDS` | `5` | How often the server re-reads the manifest |
| `AGENT_LLM_INFO_FILE` | none | Override LLM configuration file |
| `AGENT_NETWORK_DESIGNER_MANIFEST_FILE` | `registries/manifest_and.hocon` | Manifest for Agent Network Designer |

### Observability (optional)

| Variable | Default | Purpose |
|---|---|---|
| `PHOENIX_ENABLED` | `false` | Enable Phoenix tracing UI |
| `PHOENIX_HOST` | `127.0.0.1` | Phoenix server host |
| `PHOENIX_PORT` | `6006` | Phoenix server port |
| `LANGFUSE_ENABLED` | `false` | Enable Langfuse observability |
| `LANGFUSE_SECRET_KEY` | none | Langfuse secret key |
| `LANGFUSE_PUBLIC_KEY` | none | Langfuse public key |
| `LANGFUSE_HOST` | `https://cloud.langfuse.com` | Langfuse host |
| `LANGSMITH_TRACING` | `false` | Enable LangSmith tracing |
| `LANGSMITH_API_KEY` | none | LangSmith API key |

### Minimal `.env` to start a network

```bash
# Required
AGENT_MANIFEST_FILE=./registries/manifest.hocon
AGENT_TOOL_PATH=./coded_tools
AGENT_TOOLBOX_INFO_FILE=./toolbox/toolbox_info.hocon
MCP_SERVERS_INFO_FILE=./mcp/mcp_info.hocon

# At least one LLM provider
OPENAI_API_KEY=sk-...
# or ANTHROPIC_API_KEY=sk-ant-...
# or GOOGLE_API_KEY=...
```

---

## 19. VALIDATING A NETWORK WITH THE HOCON VALIDATOR CLI

Before running the server, validate your HOCON file with the built-in CLI. Run all commands from the **repo root** directory so that `include` paths (e.g. `include "registries/aaosa_basic.hocon"`) resolve correctly.

### Basic usage

```bash
# Validate a network file
python -m neuro_san.client.hocon_validator_cli registries/basic/my_network.hocon

# Validate with verbose output — prints agent summary and metadata
python -m neuro_san.client.hocon_validator_cli registries/basic/my_network.hocon --verbose

# Validate a file outside the project directory, specifying the registry root explicitly
python -m neuro_san.client.hocon_validator_cli /tmp/my_agent.hocon --registry-dir /path/to/neuro-san-studio
```

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Validation passed — no errors |
| `1` | Validation failed — one or more errors found |
| `2` | File not found, HOCON parse error, or other fatal error |

### What the validator checks

- **Missing nodes** — agents referenced in `"tools"` lists that are not defined in the network
- **Unreachable nodes** — agents defined but never referenced by any other agent
- **Invalid tool names** — tool names that don't match any defined agent, coded tool, toolbox entry, or external agent
- **Keyword violations** — reserved or disallowed field names used incorrectly
- **Structure errors** — missing required fields, wrong types, malformed `function.parameters`
- **Empty instructions** — LLM agents with blank `instructions` fields
- **Invalid URL references** — malformed or unreachable external agent URLs

### Networks with external agents

If your network references external agent networks (e.g. `"/agent_network_designer"`), validation will fail unless you explicitly declare them with `--external-agents`:

```bash
python -m neuro_san.client.hocon_validator_cli registries/my_network.hocon \
    --external-agents '/agent_network_designer,/expedia' \
    --verbose
```

Pass a comma-separated list of external agent names, each starting with `/`.

### Networks with MCP servers

Similarly, declare any MCP server URLs with `--mcp-servers`:

```bash
python -m neuro_san.client.hocon_validator_cli registries/my_network.hocon \
    --mcp-servers 'https://mcp.example.com/server' \
    --verbose
```

### JSON output (for CI/scripting)

```bash
python -m neuro_san.client.hocon_validator_cli registries/my_network.hocon --json-output
```

### Registry directory resolution

The validator needs to know the project root so it can resolve `include` statements. It determines this in order:

1. Parent of the parent of `AGENT_MANIFEST_FILE` (if the env var is set)
2. Current working directory (fallback)
3. Explicit `--registry-dir` flag (overrides both)

If you get "file not found" errors on `include` paths, either set `AGENT_MANIFEST_FILE` or pass `--registry-dir`:

```bash
# Best practice: set AGENT_MANIFEST_FILE before validating
export AGENT_MANIFEST_FILE=./registries/manifest.hocon
python -m neuro_san.client.hocon_validator_cli registries/basic/my_network.hocon --verbose
```

### Example verbose output

```
Validation passed: No errors found.

--- Agent Network Summary ---
Total agents/tools defined: 4

Agents:
  - SupportRouter (LLM Agent)
      Sub-tools: OrdersExpert, AccountExpert
  - OrdersExpert (LLM Agent)
      Sub-tools: OrdersDB
  - AccountExpert (LLM Agent)
  - OrdersDB (Coded Tool)

Metadata: {
  "description": "Customer support router.",
  "sample_queries": ["I need help with my order."]
}
```

---

## 20. RUNNING AND TESTING

```bash
# Start the server
export AGENT_MANIFEST_FILE="./registries/manifest.hocon"
export AGENT_TOOL_PATH="./coded_tools"
export OPENAI_API_KEY="sk-..."
python -m run

# Access UI at http://localhost:4173/

# Run integration tests
pytest -s -m "integration"
pytest -s -m "integration_basic_my_network"   # specific network
```

Test fixtures live in `tests/fixtures/` as HOCON files that define interactions and expected responses.
