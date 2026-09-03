# Coded Tool Patterns

---

## Template A — async I/O (the default choice)

```python
import logging
from typing import Any
from typing import Dict
from typing import Union

import aiohttp

from neuro_san.interfaces.coded_tool import CodedTool


class FetchData(CodedTool):
    """Fetches data from an external API."""

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        logger = logging.getLogger(self.__class__.__name__)
        logger.debug("========== Calling %s ==========", self.__class__.__name__)

        url: str = args.get("url")
        if not url:
            return "Error: 'url' is required."

        api_key: str = sly_data.get("api_key")
        headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}

        async with aiohttp.ClientSession() as session:
            async with session.get(url, headers=headers, timeout=aiohttp.ClientTimeout(total=30)) as resp:
                if resp.status != 200:
                    logger.error("HTTP %s from %s", resp.status, url)
                    return f"Error: HTTP {resp.status} from {url}"
                data = await resp.json()

        return {"data": data}
```

## Template B — simple synchronous, delegating

Only when the work is genuinely non-blocking (pure computation, dict lookup).

```python
import logging
from typing import Any
from typing import Dict
from typing import Union

from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)


class Classify(CodedTool):
    """Classifies input text against a fixed rule set."""

    def invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        text: str = args.get("text")
        if not text:
            return "Error: 'text' is required."
        return {"category": self._classify(text)}

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        """Delegates to the synchronous invoke because the work is quick and non-blocking."""
        return self.invoke(args, sly_data)

    @staticmethod
    def _classify(text: str) -> str:
        return "greeting" if text.lower().startswith("hello") else "other"
```

## Template C — blocking library wrapped for async

```python
import asyncio
import logging
from typing import Any
from typing import Dict
from typing import Union

import requests

from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)


class SyncWrappedTool(CodedTool):
    """Uses the blocking requests library, kept off the event loop."""

    def invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        query: str = args.get("query", "")
        if not query:
            return "Error: 'query' is required."

        response = requests.get("https://api.example.com/search", params={"q": query}, timeout=10)
        response.raise_for_status()
        return response.json()

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        return await asyncio.to_thread(self.invoke, args, sly_data)
```

## Template D — env-var configuration

```python
import logging
import os
from typing import Any
from typing import Dict
from typing import Union

from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)


class ConfiguredTool(CodedTool):
    """Reads configuration from environment variables at construction."""

    def __init__(self):
        self.api_key = os.getenv("MY_SERVICE_API_KEY")
        self.base_url = os.getenv("MY_SERVICE_BASE_URL", "https://api.default.com")
        if not self.api_key:
            logger.error("MY_SERVICE_API_KEY is not set")

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Union[Dict[str, Any], str]:
        if not self.api_key:
            return "Error: MY_SERVICE_API_KEY is not configured."
        ...
```

Prefer `os.getenv("KEY")` (returns `None`) over `os.environ["KEY"]` (raises `KeyError`).
Use `sly_data` instead when a secret must vary per request.

---

## Args patterns

```python
# Required
name: str = args.get("name")
if not name:
    return "Error: 'name' is required."

# Optional with default
limit: int = int(args.get("limit", 10))

# Coercion — the LLM may send numbers as strings
amount: float = float(args.get("amount", 0))

# List and nested dict
items: list = args.get("items", [])
options: dict = args.get("options", {})
mode: str = options.get("mode", "default")

# args first, sly_data as fallback
customer: str = args.get("customer_name") or sly_data.get("username")
```

Remember `args` also carries `origin`, `origin_str`, `progress_reporter`, and possibly
`reservationist`. Never iterate `args` assuming it holds only your declared parameters.

---

## sly_data patterns

Never appears in an LLM prompt. Use it for secrets, session state, and cross-tool sharing.

```python
# Read a secret
api_key: str = sly_data.get("api_key")
if not api_key:
    return "Error: api_key not available in sly_data."

# Bulletin board — first writer wins
if sly_data.get("username") is None:
    sly_data["username"] = discovered_username

# Update a running total
current: float = float(sly_data.get("running_cost", 0.0))
sly_data["running_cost"] = current + cost_delta

# Accumulate structured state
memory: dict = sly_data.get("session_memory", {})
memory[topic] = memory.get(topic, "") + "\n" + new_fact
sly_data["session_memory"] = memory
```

Within one network sly_data flows freely between coded tools. Crossing a **network
boundary** requires an `allow` block on the calling agent:

```hocon
"allow": {
    "to_downstream":   { "sly_data": ["api_key"] },
    "from_downstream": { "sly_data": ["session_memory"] },
    "to_upstream":     { "sly_data": ["running_cost"] }
}
```

The upstream docs warn that a bulletin-board write is only safe when the writing tool is
invoked **once** — otherwise two invocations race. Guard with the "first writer wins" check
when that isn't guaranteed.

---

## Return value patterns

| Return | Use for |
|---|---|
| `dict` | Structured result — the recommended default |
| `list[dict]` | Multiple results: search hits, records |
| `str` | Simple text answer |
| `"Error: ..."` | Validation failure the LLM should handle gracefully |
| raise | Genuine framework-level failure |

```python
return {"order_id": "ORD-123", "status": "placed", "eta": "2 days"}
return [{"title": "...", "url": "...", "snippet": "..."}]
return f"Order {order_id} placed for {customer_name}."
return "Error: No matching shop found. Known shops: Bob's, Joe's."
raise ValueError("invalid_input: 'url' is not a valid HTTP URL.")
```

Prefer returning an error string over raising: the LLM sees it and can recover or ask the
user, whereas an exception surfaces as a hard failure. Include actionable detail — listing
the valid options, as in the example above, measurably improves recovery.

---

## Logging

```python
logger = logging.getLogger(self.__class__.__name__)
logger.debug("========== Calling %s ==========", self.__class__.__name__)
logger.debug(">>> %s args=%s", self.__class__.__name__, args)
logger.error("HTTP %s from %s", resp.status, url)
```

- `logger.debug()` for arg/result tracing
- `logger.info()` for lifecycle events
- `logger.error()` before returning an error string
- `%s` lazy formatting, not f-strings
- **Never log `sly_data`**, and be careful logging `args` if secrets can arrive there

The studio has an `AndLogger` wrapper that demotes INFO to DEBUG unless
`AGENT_NETWORK_DESIGNER_VERBOSE` is set, with an `always_info()` escape hatch — used by
Designer tools to stay quiet by default.
