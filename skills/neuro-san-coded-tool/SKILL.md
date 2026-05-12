---
name: neuro-san-coded-tool
description: Create coded tools (Python classes) for neuro-san agent networks. Use this skill when implementing a CodedTool class, wiring it into a HOCON file, handling args and sly_data, writing async or sync invoke methods, dealing with external APIs or databases, returning structured results, writing unit tests, or debugging class resolution issues.
when_to_use: When asked to create a coded tool, implement a Python tool for a neuro-san agent, add a class field to a HOCON agent definition, handle sly_data in Python, write tests for a coded tool, or troubleshoot import/class resolution errors in neuro-san.
argument-hint: [tool-name] [what-it-does]
allowed-tools: Read Bash
---

# Neuro-SAN Coded Tool Skill

You are an expert in writing Python `CodedTool` implementations for the neuro-san framework. Use this reference to create, wire, and test coded tools correctly.

---

## 1. WHAT IS A CODED TOOL?

A `CodedTool` is a Python class that implements non-LLM logic inside an agent network — database queries, HTTP calls, computations, file I/O, external API integrations, etc. The framework calls either `async_invoke()` or `invoke()` when the LLM agent decides to use the tool.

---

## 2. CODED TOOLS AND AAOSA

Coded tools are **leaf nodes** in the agent network. They are called by LLM agents and have no awareness of the AAOSA protocol. Specifically:

- Do **not** add `${aaosa_call}`, `${aaosa_instructions}`, or `${aaosa_command}` to a coded tool's HOCON definition
- Do **not** implement Determine/Fulfill/Follow up logic in Python — that is handled by LLM agents
- A coded tool's HOCON agent **does not** use `"command"` — only AAOSA sub-agents do
- Coded tools never call other agents (unless using the `CallAgent`/`BranchActivation` pattern from the framework internals)

The typical position of a coded tool in an AAOSA network: an AAOSA sub-agent calls the coded tool to fulfill the concrete work after it has decided to handle the inquiry.

```
User → FrontMan (AAOSA)
         └─→ SpecialistA (AAOSA sub-agent, mode: Fulfill)
                  └─→ MyCodedTool  ← this is where your Python class is called
```

---

## 3. REGISTERING A CODED TOOL IN THE TOOLBOX

A coded tool can be used in two ways:

| Approach | When to use |
|---|---|
| **Network-scoped** — `"class": "module.Class"` in the agent HOCON | Tool is specific to one network; lives in `coded_tools/<network>/` |
| **Toolbox-registered** — `"toolbox": "tool_name"` in the agent HOCON | Tool is reusable across many networks; registered in `toolbox/toolbox_info.hocon` |

### Toolbox entry schema

Add an entry to `toolbox/toolbox_info.hocon`:

```hocon
# toolbox/toolbox_info.hocon

"my_tool_name": {
    # Required: Python import path to the CodedTool subclass
    # Resolved from AGENT_TOOL_PATH (coded_tools/) or LangChain's namespace
    "class": "coded_tools.tools.my_module.MyToolClass",

    # Required for coded tools: what the tool does (shown to the LLM)
    "description": "A short description of what this tool does.",

    # Required for coded tools: parameter schema (JSON Schema, same as in agent HOCON)
    "parameters": {
        "type": "object",
        "properties": {
            "query": { "type": "string", "description": "The search query." },
            "limit": { "type": "integer", "description": "Max results." }
        },
        "required": ["query"]
    },

    # Optional: default constructor args — agents can override per-use with their own "args" block
    "args": {
        "limit": 5,
        "timeout": 30
    },

    # Optional: documentation URL for human reference
    "base_tool_info_url": "https://docs.example.com/my-tool"
}
```

### Using the registered tool in an agent network

```hocon
# In any .hocon network file — no "function", "instructions", or "class" needed
{
    "name": "MySearchAgent",
    "toolbox": "my_tool_name"
}

# Override defaults per-agent:
{
    "name": "MySearchAgentFast",
    "toolbox": "my_tool_name",
    "args": { "limit": 3, "timeout": 10 }
}
```

HOCON `args` on the agent are **merged on top of** toolbox defaults — only specified keys are overridden.

### Registering a LangChain tool or toolkit

The same schema works for any LangChain tool or toolkit class. For toolkits (classes with `.get_tools()`), the framework calls `.get_tools()` automatically and registers all the sub-tools.

```hocon
# LangChain tool (single tool)
"tavily_search": {
    "class": "langchain_tavily.TavilySearch",
    "base_tool_info_url": "https://pypi.org/project/langchain-tavily/",
    "args": {
        "max_results": 5,
        "topic": "general"
    }
}

# LangChain toolkit (multiple tools exposed at once)
"jira_toolkit": {
    "class": "langchain_community.agent_toolkits.jira.toolkit.JiraToolkit",
    "args": {
        "jira_api_wrapper": {
            "class": "langchain_community.utilities.jira.JiraAPIWrapper"
        }
    }
}
```

### Toolbox file location and env var

- Default studio toolbox: `toolbox/toolbox_info.hocon`
- Controlled by: `AGENT_TOOLBOX_INFO_FILE` env var
- The core neuro-san library has its own default toolbox (always loaded) with: `requests_get`, `requests_post`, `requests_patch`, `requests_put`, `requests_delete`, `requests_toolkit`, `get_current_date_time`

### Decision: network-scoped tool vs toolbox entry

Add to the toolbox when:
- The tool will be used in **3 or more different networks**
- The tool is a general utility (web search, RAG, HTTP, date/time)
- You want a clean `"toolbox": "name"` reference instead of a verbose `"class"` path

Keep as network-scoped when:
- The tool is tightly coupled to one network's domain logic
- The tool reads from files or config specific to that network
- You don't want to expose it to other networks

---

## 4. THE CODEDTOOL BASE CLASS

```python
from neuro_san.interfaces.coded_tool import CodedTool
from typing import Any, Dict, Union

class MyTool(CodedTool):

    async def async_invoke(
        self, args: Dict[str, Any], sly_data: Dict[str, Any]
    ) -> Union[Dict[str, Any], str]:
        ...

    def invoke(
        self, args: Dict[str, Any], sly_data: Dict[str, Any]
    ) -> Union[Dict[str, Any], str]:
        ...
```

### Calling contract
- **`args`** — dict of values from the LLM + any `args` block in the HOCON spec. Treat as **read-only**.
- **`sly_data`** — dict of sensitive/shared data that never appears in LLM prompts. Largely read-only, but tools may write new keys to use it as a bulletin board (see §7).
- **Return value** — anything returned goes directly into the chat stream. Return a `dict`, a `list`, or a plain `str`.

### Which method to implement
| Scenario | Method |
|---|---|
| Any I/O: HTTP, DB, file, sleep | `async_invoke()` — **preferred always** |
| Simple, guaranteed non-blocking | `invoke()` — acceptable |
| Blocking sync library in async context | `async_invoke()` calling `asyncio.to_thread(self.invoke, args, sly_data)` |

The base class default: `invoke()` is a no-op; `async_invoke()` raises `NotImplementedError`. Override at least one.

---

## 5. FILE PLACEMENT AND MODULE RESOLUTION

### Directory layout
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

Set `AGENT_TOOL_PATH` env var to the `coded_tools/` parent directory. Always include an `__init__.py` in every subdirectory.

### How the `class` field resolves

Given `"class": "my_tool.MyTool"` inside a network called `my_network_name`, the framework tries in order:

1. Direct fully-qualified import: `my_tool.MyTool`
2. `coded_tools.my_network_name.my_tool.MyTool`  ← most specific
3. `coded_tools.my_tool.MyTool`                  ← root shared
4. `my_tool.MyTool`                              ← bare fallback

**Rule of thumb:** if the file is inside a `coded_tools/<network>/` subdirectory, just use `"class": "module_filename.ClassName"`. If the file is at the `coded_tools/` root, the same short form still works.

### Constructor constraint
The framework instantiates tools with a **zero-argument constructor** (`MyTool()`). Any `__init__` must take no required parameters. Read config from env vars or use the `args` dict at call time.

```python
# OK — no-arg __init__
class BraveSearch(CodedTool):
    def __init__(self):
        self.api_key = os.getenv("BRAVE_API_KEY")

# NOT OK — requires argument
class MyTool(CodedTool):
    def __init__(self, api_key: str):  # framework can't call this
        ...
```

---

## 6. WIRING INTO HOCON

```hocon
{
    "name": "MyTool",
    "function": {
        "description": "Does X when given Y.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": { "type": "string", "description": "The search query." },
                "limit": { "type": "integer", "description": "Max results to return." }
            },
            "required": ["query"]
        }
    },
    "class": "my_tool.MyTool",
    "args": {
        "limit": 10   # HOCON args override LLM-provided args of the same key
    }
}
```

### args merging rule
HOCON `args` values **win** over LLM-provided values for the same key. Use HOCON `args` for hard defaults or forced overrides; use `function.parameters.properties` defaults for soft defaults (let LLM set them).

---

## 7. COMPLETE TOOL TEMPLATES

### Template A — simple synchronous (non-blocking)

```python
import logging
from typing import Any, Dict, Union

from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)


class SimpleToolName(CodedTool):
    """One-line description of what this tool does."""

    def invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        logger.debug(">>> %s called with args=%s", self.__class__.__name__, args)

        value: str = args.get("input_param")
        if not value:
            return "Error: 'input_param' is required."

        result = do_something(value)

        logger.debug(">>> %s returning %s", self.__class__.__name__, result)
        return {"result": result}

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        return self.invoke(args, sly_data)
```

### Template B — async I/O (HTTP, DB, file)

```python
import logging
from typing import Any, Dict, Union

import aiohttp
from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)


class AsyncToolName(CodedTool):
    """Fetches data from an external API."""

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        logger.debug(">>> %s called with args=%s", self.__class__.__name__, args)

        url: str = args.get("url")
        if not url:
            return "Error: 'url' is required."

        api_key: str = sly_data.get("api_key")

        async with aiohttp.ClientSession() as session:
            async with session.get(url, headers={"Authorization": f"Bearer {api_key}"}) as resp:
                if resp.status != 200:
                    return f"Error: HTTP {resp.status} from {url}"
                data = await resp.json()

        return {"data": data}
```

### Template C — blocking sync library wrapped for async

```python
import asyncio
import logging
from typing import Any, Dict, Union

import requests
from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)


class SyncWrappedTool(CodedTool):
    """Uses a blocking requests library, wrapped for async safety."""

    def invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        query: str = args.get("query", "")
        if not query:
            return "Error: 'query' is required."

        response = requests.get("https://api.example.com/search", params={"q": query}, timeout=10)
        response.raise_for_status()
        return response.json()

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        # Run blocking invoke() in a thread so it doesn't block the event loop
        return await asyncio.to_thread(self.invoke, args, sly_data)
```

### Template D — constructor state + env var config

```python
import logging
import os
from typing import Any, Dict, Union

from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)


class ConfiguredTool(CodedTool):
    """Tool that reads config from environment variables at startup."""

    def __init__(self):
        self.api_key = os.getenv("MY_SERVICE_API_KEY")
        self.base_url = os.getenv("MY_SERVICE_BASE_URL", "https://api.default.com")
        if not self.api_key:
            logger.error("MY_SERVICE_API_KEY is not set")

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        if not self.api_key:
            return "Error: MY_SERVICE_API_KEY environment variable is not configured."
        # ... use self.api_key and self.base_url ...
```

---

## 8. ARGS PATTERNS

### Reading args with fallback and validation
```python
# Required arg
name: str = args.get("name")
if not name:
    return "Error: 'name' is required."

# Optional with default
limit: int = int(args.get("limit", 10))

# Type coercion (LLM may pass numbers as strings)
amount: float = float(args.get("amount", 0))

# List arg
items: list = args.get("items", [])

# Nested dict arg
options: dict = args.get("options", {})
mode: str = options.get("mode", "default")
```

### Priority: try args first, fall back to sly_data
```python
# Pattern from real tools: args takes priority, sly_data is fallback
customer_name: str = args.get("customer_name") or sly_data.get("username")
if not customer_name:
    return "Error: customer name is required."
```

---

## 9. SLY_DATA PATTERNS

`sly_data` is a shared side-channel dict — values never appear in LLM context. Use it for secrets, session state, and cross-tool shared data.

### Read-only: consume a secret
```python
api_key: str = sly_data.get("api_key")
if not api_key:
    return "Error: api_key not available in sly_data."
```

### Bulletin board: write new key (first writer wins)
```python
# Only set if not already set — first caller establishes the value
if sly_data.get("username") is None:
    sly_data["username"] = discovered_username
```

### Update existing value
```python
# Increment a counter
current: float = float(sly_data.get("running_cost", 0.0))
sly_data["running_cost"] = current + cost_delta
```

### Accumulate state across calls
```python
# Read existing state, update, write back
memory: dict = sly_data.get("session_memory", {})
memory[topic] = memory.get(topic, "") + "\n" + new_fact
sly_data["session_memory"] = memory
```

### sly_data must be configured in HOCON to flow
For `sly_data` keys to pass between agents and external networks, you must declare them in the calling agent's `allow` block:
```hocon
"allow": {
    "to_downstream":   { "sly_data": ["api_key"] },
    "from_downstream": { "sly_data": ["session_memory"] }
}
```
Within the same network, `sly_data` flows freely between all coded tools.

---

## 10. RETURN VALUE PATTERNS

| Return type | When to use |
|---|---|
| `dict` | Structured result with named fields; recommended default |
| `list` of `dict` | Multiple results (search hits, records, etc.) |
| `str` | Simple text answer or plain error message |
| `"Error: ..."` string | Validation failure the LLM should handle gracefully |
| Raise `ValueError` | Framework-level failure (agent re-tries or surfaces to user) |

```python
# Structured dict return
return {"order_id": "ORD-123", "status": "placed", "eta": "2 days"}

# List of dicts return
return [{"title": "...", "url": "...", "snippet": "..."}]

# Plain string
return f"Order {order_id} placed successfully for {customer_name}."

# Error as string (LLM handles it)
return "Error: No matching shop found. Known shops: Bob's, Joe's."

# Raise for framework-level errors
raise ValueError("invalid_input: 'url' parameter is not a valid HTTP URL.")
```

---

## 11. LOGGING BEST PRACTICES

```python
import logging
logger = logging.getLogger(__name__)

async def async_invoke(self, args, sly_data):
    logger.debug(">>> %s args=%s", self.__class__.__name__, args)
    # ... work ...
    logger.debug(">>> %s result=%s", self.__class__.__name__, result)
    return result
```

- Use `logger.debug()` for arg/result tracing (won't appear in production unless DEBUG is set)
- Use `logger.info()` for key lifecycle events
- Use `logger.error()` for failures before returning an error string
- Never log raw `sly_data` — it contains sensitive values

---

## 12. REAL-WORLD EXAMPLES

### External REST API call (async)
```python
import logging
import os
import aiohttp
from typing import Any, Dict, List, Union
from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)

class SearchTool(CodedTool):
    def __init__(self):
        self.api_key = os.getenv("SEARCH_API_KEY")

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[List[Dict], str]:
        query: str = args.get("query")
        if not query:
            return "Error: 'query' is required."
        limit: int = int(args.get("limit", 5))

        headers = {"X-API-Key": self.api_key or sly_data.get("search_api_key", "")}
        params = {"q": query, "count": limit}

        async with aiohttp.ClientSession() as session:
            async with session.get("https://api.search.com/v1/search", headers=headers, params=params) as resp:
                if resp.status != 200:
                    return f"Error: Search API returned HTTP {resp.status}."
                data = await resp.json()

        results = []
        for item in data.get("results", []):
            results.append({"title": item["title"], "url": item["url"], "snippet": item.get("description", "")})
        return results
```

### Database lookup (async)
```python
import asyncpg
import logging
import os
from typing import Any, Dict, Union
from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)

class ProductLookup(CodedTool):
    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict, str]:
        product_id: str = args.get("product_id")
        if not product_id:
            return "Error: 'product_id' is required."

        db_url = os.getenv("DATABASE_URL")
        conn = await asyncpg.connect(db_url)
        try:
            row = await conn.fetchrow("SELECT id, name, price, stock FROM products WHERE id = $1", product_id)
            if not row:
                return f"Error: No product found with id '{product_id}'."
            return {"id": row["id"], "name": row["name"], "price": float(row["price"]), "stock": row["stock"]}
        finally:
            await conn.close()
```

### Accumulating shared memory via sly_data
```python
import json
import logging
from typing import Any, Dict, Union
from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)

class AddToCart(CodedTool):
    def invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict, str]:
        item: str = args.get("item")
        quantity: int = int(args.get("quantity", 1))
        if not item:
            return "Error: 'item' is required."

        cart: Dict[str, int] = sly_data.get("cart", {})
        cart[item] = cart.get(item, 0) + quantity
        sly_data["cart"] = cart

        return {"cart": cart, "message": f"Added {quantity}x {item} to cart."}

    async def async_invoke(self, args, sly_data):
        return self.invoke(args, sly_data)
```

---

## 13. UNIT TESTING

Use `IsolatedAsyncioTestCase` for async tools.

```python
from unittest import IsolatedAsyncioTestCase
import pytest

from coded_tools.my_network.my_tool import MyTool


class TestMyTool(IsolatedAsyncioTestCase):

    async def test_basic_call(self):
        tool = MyTool()
        result = await tool.async_invoke(
            args={"query": "hello"},
            sly_data={}
        )
        self.assertIsInstance(result, dict)
        self.assertIn("result", result)

    async def test_missing_required_arg(self):
        tool = MyTool()
        result = await tool.async_invoke(args={}, sly_data={})
        self.assertIn("Error", result)

    async def test_sly_data_read(self):
        tool = MyTool()
        result = await tool.async_invoke(
            args={},
            sly_data={"api_key": "test-key", "username": "alice"}
        )
        self.assertNotIn("Error", str(result))

    async def test_sly_data_write(self):
        tool = MyTool()
        sly_data = {}
        await tool.async_invoke(args={"item": "coffee", "quantity": 2}, sly_data=sly_data)
        self.assertIn("cart", sly_data)
        self.assertEqual(sly_data["cart"]["coffee"], 2)
```

Run with:
```bash
pytest tests/ -v
pytest tests/coded_tools/my_network/test_my_tool.py -v
```

---

## 14. COMMON PITFALLS

| Mistake | Fix |
|---|---|
| `__init__` requires arguments | Remove required params — framework calls `MyTool()` with no args |
| Using `requests` in `async_invoke` directly | Wrap with `asyncio.to_thread(self.invoke, args, sly_data)` |
| Writing to `args` dict | `args` is read-only; use local variables instead |
| Logging `sly_data` | Never log it — it contains secrets |
| `class` path includes `coded_tools.` prefix | Usually not needed; framework adds it via progressive resolution |
| Missing `__init__.py` in subdirectory | Add one or module won't be importable |
| sly_data key not flowing to coded tool | Check the calling agent's `allow.to_downstream.sly_data` list |
| HOCON `args` not overriding LLM value | They do override — if you want LLM to control a value, remove it from HOCON `args` |
| Returning `None` from invoke | Return a string or dict; `None` causes the framework to use the base class no-op return |

---

## 15. ENVIRONMENT VARIABLES

Coded tools read env vars at `__init__` time or inside `async_invoke`/`invoke`. Below are all variables the framework and common coded tools depend on.

### Core framework (required for tools to be discovered and loaded)

| Variable | Default | Purpose |
|---|---|---|
| `AGENT_TOOL_PATH` | `coded_tools/` | Root directory where the framework looks for coded tool modules |
| `AGENT_MANIFEST_FILE` | `registries/manifest.hocon` | Which networks are served (and therefore which tools are loaded) |
| `AGENT_TOOLBOX_INFO_FILE` | `toolbox/toolbox_info.hocon` | Toolbox built-in tools config (e.g. `tavily_search`) |

### LLM provider keys (at least one required)

| Variable | Provider |
|---|---|
| `OPENAI_API_KEY` | OpenAI |
| `ANTHROPIC_API_KEY` | Anthropic Claude |
| `GOOGLE_API_KEY` | Google Gemini |
| `AZURE_OPENAI_API_KEY` + `AZURE_OPENAI_ENDPOINT` + `OPENAI_API_VERSION` + `AZURE_OPENAI_DEPLOYMENT_NAME` | Azure OpenAI |
| `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` | AWS Bedrock |

### Search & web tools

| Variable | Default | Used by |
|---|---|---|
| `TAVILY_API_KEY` | none | `tavily_search` toolbox tool |
| `BRAVE_API_KEY` | none | `BraveSearch` coded tool |
| `BRAVE_URL` | `https://api.search.brave.com/res/v1/web/search?q=` | `BraveSearch` |
| `BRAVE_TIMEOUT` | `30` | `BraveSearch` |
| `GOOGLE_SEARCH_API_KEY` | none | `GoogleSearch` coded tool |
| `GOOGLE_SEARCH_CSE_ID` | none | `GoogleSearch` custom search engine ID |
| `YDC_API_KEY` | none | You.com search |
| `SERPER_API_KEY` | none | Serper search |
| `NYT_API_KEY` | none | New York Times news tool |
| `GUARDIAN_API_KEY` | none | Guardian news tool |

### Database (PostgreSQL — used by RAG tools)

| Variable | Purpose |
|---|---|
| `POSTGRES_USER` | PostgreSQL username |
| `POSTGRES_PASSWORD` | PostgreSQL password |
| `POSTGRES_HOST` | PostgreSQL host |
| `POSTGRES_PORT` | PostgreSQL port |
| `POSTGRES_DB` | PostgreSQL database name |

### Atlassian / Jira / Confluence

| Variable | Purpose |
|---|---|
| `JIRA_USERNAME` | Jira/Confluence username |
| `JIRA_API_TOKEN` | Jira/Confluence API token |

### Enterprise integrations

| Variable | Purpose |
|---|---|
| `SERVICENOW_INSTANCE_URL` | ServiceNow instance URL |
| `SERVICENOW_USER` | ServiceNow username |
| `SERVICENOW_PWD` | ServiceNow password |
| `AGENTFORCE_MY_DOMAIN_URL` | Salesforce Agentforce domain |
| `AGENTFORCE_AGENT_ID` | Agentforce agent ID |
| `AGENTFORCE_CLIENT_ID` | Agentforce OAuth client ID |
| `AGENTFORCE_CLIENT_SECRET` | Agentforce OAuth client secret |
| `GOOGLE_APPLICATION_CREDENTIALS` | GCP service account credentials file path |
| `GCP_PROJECT_ID` | GCP project ID (default: framework default) |

### Authorization (OpenFGA — optional)

| Variable | Default | Purpose |
|---|---|---|
| `FGA_API_URL` | none | OpenFGA API URL |
| `FGA_API_TOKEN` | none | OpenFGA API token |
| `FGA_MODEL_ID` | none | OpenFGA model ID |
| `FGA_STORE_NAME` | `default` | OpenFGA store name |
| `AGENT_AUTHORIZER` | none | Authorizer class (leave unset to skip auth) |

### Reading env vars inside a coded tool

```python
import os

class MyTool(CodedTool):
    def __init__(self):
        # Read at init — fails fast if missing
        self.api_key = os.getenv("MY_SERVICE_API_KEY")
        if not self.api_key:
            logger.error("MY_SERVICE_API_KEY is not set")

    async def async_invoke(self, args, sly_data):
        if not self.api_key:
            return "Error: MY_SERVICE_API_KEY environment variable is not configured."
        # ... use self.api_key ...
```

**Prefer `os.getenv("KEY")` (returns `None`) over `os.environ["KEY"]` (raises `KeyError`) for optional vars.**
Use `sly_data` when a secret needs to vary per-request (e.g. a per-user API token injected by the client).

---

## 16. HOCON + CODED TOOL CHECKLIST

- [ ] Python file in `coded_tools/<network>/my_tool.py` (or `coded_tools/my_tool.py` for shared)
- [ ] `__init__.py` in every subdirectory of `coded_tools/`
- [ ] Class inherits from `CodedTool`
- [ ] At least `async_invoke()` or `invoke()` overridden
- [ ] `__init__` takes no required parameters
- [ ] HOCON agent has `"class": "my_tool.MyTool"`
- [ ] HOCON `function.parameters` matches what `args` dict will contain
- [ ] HOCON `args` block used for hard overrides (optional)
- [ ] Calling agent's `allow` block declares any `sly_data` keys the tool reads/writes (for cross-network flows)
- [ ] Unit test in `tests/coded_tools/<network>/test_my_tool.py`
- [ ] No secrets hardcoded — use `os.getenv()` or `sly_data`
