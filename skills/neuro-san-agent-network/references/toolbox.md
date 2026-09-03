# Toolbox Reference

The toolbox is a catalog of pre-configured tools any network can use by name — no Python
required. Two layers stack: the core neuro-san default toolbox, plus whatever the project
adds on top.

```hocon
{ "name": "WebSearch", "toolbox": "ddgs_search" }
```

No `function`, `instructions`, or `class` needed — all of that comes from the toolbox entry.
An agent using `toolbox` **cannot also have `tools`**, and cannot be the front man.

Override constructor args per use; HOCON `args` merge **on top of** the toolbox defaults, so
only the keys you name change:

```hocon
{ "name": "WebSearch", "toolbox": "tavily_search",
  "args": { "max_results": 10, "search_depth": "advanced" } }
```

---

## Default toolbox — one tool

`neuro_san/internals/run_context/langchain/toolbox/toolbox_info.hocon`

| Tool | What it does |
|---|---|
| `get_current_date_time` | Current date/time. Params: `utc_offset` (int, −24..24, takes precedence) and `iana_timezone` |

### The HTTP tools were removed

`requests_get`, `requests_post`, `requests_put`, `requests_patch`, `requests_delete`, and
`requests_toolkit` **no longer exist**. They were built on the deprecated
`langchain-community` package and shipped `allow_dangerous_requests=true`. Referencing any of
them now raises a specific removal error.

Replacements:

- For fetching a URL, use the studio's `web_fetch` tool (allow/block lists, size caps)
- For arbitrary HTTP, define your own toolbox entry via `AGENT_TOOLBOX_INFO_FILE` or the
  `toolbox_info_file` HOCON key, and harden it against SSRF yourself

Some upstream docs still list the `requests_*` tools. They are stale — trust the code.

---

## Studio toolbox — 27 tools

`neuro_san_studio/toolbox/toolbox_info.hocon`. Additive on top of the default toolbox.

### Web search

| Tool | Requires |
|---|---|
| `ddgs_search` | nothing — no API key |
| `brave_search` | `BRAVE_API_KEY`; optional `BRAVE_URL`, `BRAVE_TIMEOUT` |
| `google_search` | `GOOGLE_SEARCH_API_KEY`, `GOOGLE_SEARCH_CSE_ID` |
| `google_serper` | `SERPER_API_KEY`. Params: `query`, `type` (search/news/images/places), `k`, `gl`, `hl`, `tbs` |
| `tavily_search` | `TAVILY_API_KEY` + `pip install langchain-tavily` |
| `anthropic_search` | `ANTHROPIC_API_KEY` + `langchain-anthropic>=0.3.13` |
| `openai_search` | `OPENAI_API_KEY` + `langchain-openai>=0.3.26` |

### Web fetching

| Tool | Requires |
|---|---|
| `web_fetch` | `beautifulsoup4`, `aiohttp`, `pypdf`. Handles HTML and PDF. Args: `url` (http/https, ≤250 chars), allow-list domains, block-list domains, max chars (default 20000) |

### Code, image, and video generation

| Tool | Requires |
|---|---|
| `openai_code_interpreter` | `OPENAI_API_KEY`, `langchain-openai>=0.3.26` |
| `anthropic_code_execution` | `ANTHROPIC_API_KEY`, `langchain-anthropic>=0.3.13` |
| `openai_image_generation` | `OPENAI_API_KEY` |
| `openai_video_generation` | `OPENAI_API_KEY`. Params: `prompt`, existing video ID to remix |
| `gemini_image_generation` | `GOOGLE_API_KEY`, `pip install google-genai`. Params: `prompt`, aspect ratio, size (1K/2K/4K), grounding flag |

### RAG and retrieval

| Tool | Requires |
|---|---|
| `pdf_rag` | `pymupdf>=1.25.5` |
| `webpage_rag` | — (params: `query`, list of URLs) |
| `docling_rag` | `pip install langchain-docling` — Word, PPTX, and more |
| `wikipedia_rag` | `pip install wikipedia` |
| `arxiv_retriever` | `pip install arxiv` (+ `pymupdf` for full text) |
| `confluence_rag` | `pip install atlassian-python-api`; `JIRA_USERNAME`, `JIRA_API_TOKEN` |
| `wikimedia_media_search` | — (params: keywords-only query, media type, max results ≤10, offset) |

### File management — deny-by-default, read this before using

| Tool | Requires |
|---|---|
| `read_file` | `leaf-common`. Line range + char cap; files >10 MB rejected |
| `write_file` | `leaf-common`. Atomic create/overwrite; content >10 MB rejected |

Both are **deny-by-default**: they do nothing until the operator supplies `allowed_paths`
through HOCON `args`. These keys are deliberately **not** in the LLM-visible schema, so the
model cannot widen its own access:

```hocon
{
    "name": "ReadProjectFile",
    "toolbox": "read_file",
    "args": {
        "allowed_paths": ["/srv/app/data"],
        "allowed_file_extensions": [".txt", ".md", ".json"],
        "blocked_paths": ["/srv/app/data/secrets"],
        "blocked_file_extensions": [".env", ".pem"]
    }
}
```

LLM-visible params: `read_file` takes `path`, start/end line, max chars (default 20000);
`write_file` takes `path`, `content`, `overwrite` (default false), `create_parents`
(default false).

### Email and project management

| Tool | Requires |
|---|---|
| `gmail_toolkit` | `pip install -U langchain-google-community[gmail]` + `credentials.json`. No attachment support |
| `send_gmail_message_with_attachment` | same as above |
| `jira_toolkit` | `pip install atlassian-python-api`; `JIRA_API_TOKEN`, `JIRA_USERNAME`, `JIRA_INSTANCE_URL`, `JIRA_CLOUD` (or `JIRA_OAUTH2`). Ops: `jql_query`, `get_projects`, `create_issue`, `catch_all_jira_api`, `create_confluence_page` |

### Agent orchestration

| Tool | Requires |
|---|---|
| `call_agent` | — Call another network by name (`/music_nerd`, `/basic/music_nerd`) |
| `agent_network_html_generator` | `pip install pyvis` — renders a network as HTML |

---

## Registering a new tool

### Coded tool entry

Needs `description` and `parameters` — the presence of `description` is what marks the entry
as a coded tool rather than a LangChain tool.

```hocon
"my_custom_tool": {
    "class": "coded_tools.tools.my_module.MyTool",
    "description": "What this tool does.",
    "parameters": {
        "type": "object",
        "properties": { "query": { "type": "string", "description": "Input query." } },
        "required": ["query"]
    },
    "args": { "default_param": "value" },
    "display_as": "coded_tool",
    "base_tool_info_url": "https://docs.example.com/my-tool"
}
```

### LangChain tool entry — the class path rule changed

`class` must have **at least three dot-separated segments and name the module that actually
defines the class**, not a top-level re-export:

```hocon
# CORRECT
"tavily_search": { "class": "langchain_tavily.tavily_search.TavilySearch", "args": { "max_results": 5 } }

# WRONG — re-export, only two segments
"tavily_search": { "class": "langchain_tavily.TavilySearch" }
```

Toolkits (classes exposing `.get_tools()`) are detected automatically and all their sub-tools
registered. Nested `{"class": ..., "args": ...}` values inside `args` are resolved
recursively, which is how wrapper objects like API wrappers get built:

```hocon
"jira_toolkit": {
    "class": "langchain_community.agent_toolkits.jira.toolkit.JiraToolkit",
    "args": { "jira_api_wrapper": { "class": "langchain_community.utilities.jira.JiraAPIWrapper" } }
}
```

### Where the toolbox comes from

Resolution order: `AGENT_TOOLBOX_INFO_FILE` env var (set it to `""` to opt out) →
`<project>/neuro_san_studio/toolbox/toolbox_info.hocon` → the packaged copy. A
`toolbox_info_file` key in the network HOCON beats the env var.

The Agent Network Designer uses a separate curated palette at
`neuro_san_studio/toolbox/agent_network_designer_toolbox_info.hocon` — 10 tools:
`call_agent`, `openai_code_interpreter`, `openai_image_generation`,
`openai_video_generation`, `webpage_rag`, `wikimedia_media_search`, `ddgs_search`,
`web_fetch`, `read_file`, `write_file`.

---

## Note on `AGENT_TOOL_PATH_ONLY`

With `AGENT_TOOL_PATH_ONLY=true`, coded-tool class resolution is restricted to the
`AGENT_TOOL_PATH` hierarchy and fully-qualified references stop resolving. This affects
toolbox coded tools too — but **not** `llm_config.class`, middleware classes, or LangChain
toolbox classes.
