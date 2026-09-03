# Registering a Coded Tool in the Toolbox

Two ways to use a coded tool:

| Approach | When |
|---|---|
| **Network-scoped** — `"class": "module.Class"` in the agent HOCON | Specific to one network; lives in `coded_tools/<network>/` |
| **Toolbox-registered** — `"toolbox": "tool_name"` | Reusable across networks |

## Decide which

Register in the toolbox when:

- The tool is used in **3 or more networks**
- It's a general utility (search, RAG, HTTP, date/time)
- You prefer a clean `"toolbox": "name"` over a verbose `class` path

Keep it network-scoped when:

- It's tightly coupled to one network's domain logic
- It reads config or files specific to that network
- You don't want other networks using it

---

## Toolbox entry schema

`neuro_san_studio/toolbox/toolbox_info.hocon`

```hocon
"my_tool_name": {
    # Required. Resolved from AGENT_TOOL_PATH, or fully qualified.
    "class": "coded_tools.tools.my_module.MyToolClass",

    # Required for coded tools — its presence is what marks this entry as a
    # coded tool rather than a LangChain tool.
    "description": "A short description of what this tool does.",

    # Required for coded tools. Same JSON Schema as an agent's function.parameters.
    "parameters": {
        "type": "object",
        "properties": {
            "query": { "type": "string",  "description": "The search query." },
            "limit": { "type": "int",    "description": "Max results." }
        },
        "required": ["query"]
    },

    # Optional defaults; an agent's own "args" override these per use.
    "args": { "limit": 5, "timeout": 30 },

    # Optional
    "display_as": "coded_tool",
    "base_tool_info_url": "https://docs.example.com/my-tool"
}
```

Using it:

```hocon
{ "name": "MySearchAgent", "toolbox": "my_tool_name" }

{ "name": "MySearchAgentFast", "toolbox": "my_tool_name",
  "args": { "limit": 3, "timeout": 10 } }
```

Agent `args` merge **on top of** toolbox defaults — only the keys you name change.

An agent using `toolbox` **cannot also have `tools`**, and cannot be the front man.

---

## Registering a LangChain tool or toolkit

Omit `description`/`parameters` — those come from the LangChain class.

**The `class` path rule is strict:** at least three dot-separated segments, naming the module
that **defines** the class, not a top-level re-export.

```hocon
# CORRECT
"tavily_search": {
    "class": "langchain_tavily.tavily_search.TavilySearch",
    "base_tool_info_url": "https://pypi.org/project/langchain-tavily/",
    "args": { "max_results": 5, "topic": "general" }
}

# WRONG — re-export, only two segments
"tavily_search": { "class": "langchain_tavily.TavilySearch" }
```

Toolkits (classes exposing `.get_tools()`) are detected automatically and all sub-tools
registered. Nested `{"class": ..., "args": ...}` inside `args` is resolved recursively:

```hocon
"jira_toolkit": {
    "class": "langchain_community.agent_toolkits.jira.toolkit.JiraToolkit",
    "args": {
        "jira_api_wrapper": { "class": "langchain_community.utilities.jira.JiraAPIWrapper" }
    }
}
```

---

## Where the toolbox comes from

Resolution order:

1. `toolbox_info_file` key in the agent network HOCON — highest precedence
2. `AGENT_TOOLBOX_INFO_FILE` env var (set to `""` to opt out)
3. `<project>/neuro_san_studio/toolbox/toolbox_info.hocon`
4. The packaged copy

The studio toolbox is **additive** on top of neuro-san's default toolbox, which now contains
exactly one tool: `get_current_date_time`. The `requests_*` tools and `requests_toolkit`
were removed and now raise a specific removal error if referenced.

Shared studio tools live in `neuro_san_studio/coded_tools/` and are registered with
fully-qualified class paths like
`neuro_san_studio.coded_tools.anthropic_web_search.AnthropicWebSearch`.

> Fully-qualified class paths stop resolving under `AGENT_TOOL_PATH_ONLY=true`. If you need
> to support that mode, place the tool under `AGENT_TOOL_PATH` and use the short form.

---

## Security note for file/network tools

If your tool touches the filesystem or arbitrary URLs, follow the pattern the built-in
`read_file` / `write_file` tools use: make access **deny-by-default**, and take the allow-list
from operator-supplied HOCON `args` that are deliberately **absent from the LLM-visible
`parameters` schema**. That way the model can't widen its own access.

```hocon
{
    "name": "ReadProjectFile",
    "toolbox": "read_file",
    "args": {
        "allowed_paths": ["/srv/app/data"],
        "allowed_file_extensions": [".txt", ".md"],
        "blocked_paths": ["/srv/app/data/secrets"]
    }
}
```
