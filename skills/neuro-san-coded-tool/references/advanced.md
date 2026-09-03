# Advanced Coded Tool Patterns

---

## Framework-injected args

The framework adds these to `args` before calling your tool, unless already present:

| Key | Type | Notes |
|---|---|---|
| `origin` | `List[Dict[str, Any]]` | Deep copy of the run-context origin path |
| `origin_str` | `str` | This tool's full agent name |
| `progress_reporter` | `ProgressJournal` | Implements `AgentProgressReporter` |
| `reservationist` | `AccumulatingAgentReservationist` | Only when the agent spec sets `allow.reservations` |

Consequence: never iterate `args` assuming it holds only your declared parameters, and never
dump `args` wholesale into a response.

---

## Reporting progress

Streams intermediate status to the client during a long operation.

```python
async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Any:
    progress = args.get("progress_reporter")

    if progress is not None:
        await progress.async_report_progress({"step": 1, "total": 3}, "Fetching source data…")

    data = await self._fetch()

    if progress is not None:
        await progress.async_report_progress({"step": 2, "total": 3}, "Analyzing…")

    return {"result": self._analyze(data)}
```

Interface: `async_report_progress(self, structure: Dict[str, Any], content: str = "")`.
Always null-check — the key is absent if something else already populated it.

---

## Calling other agents from a coded tool

A coded tool normally cannot call agents. To fan out to other agents programmatically,
inherit from **both** `BranchActivation` and `CodedTool`:

```python
# pylint: disable=too-many-ancestors
import asyncio
from typing import Any
from typing import Dict

from neuro_san.interfaces.coded_tool import CodedTool
from neuro_san.internals.graph.activations.branch_activation import BranchActivation


class WriteAllSections(BranchActivation, CodedTool):
    """Fans out section-writing work to a downstream agent, one call per section."""

    async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Any:
        tools_map = args.get("tools") or {}
        writer_name = tools_map.get("section_writer", "section_writer")

        sections = args.get("sections", [])
        results = await asyncio.gather(
            *[
                self.use_tool(writer_name, {"section": section}, sly_data=sly_data)
                for section in sections
            ],
            return_exceptions=True,
        )

        return {"sections": [r for r in results if not isinstance(r, Exception)]}
```

### Declare the downstream agents in HOCON

`BranchActivation` gives you `use_tool()`, but the graph doesn't know about those calls
unless you declare them. Use the `args.tools` convention so connectivity reporting,
validation, and visualization stay correct:

```hocon
{
    "name": "WriteAllSections",
    "function": {
        "description": "Writes all sections of a document in parallel.",
        "parameters": {
            "type": "object",
            "properties": {
                "sections": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "Section titles to write."
                }
            },
            "required": ["sections"]
        }
    },
    "class": "write_all_sections.WriteAllSections",
    # Mirrors the decomposition_solver pattern: declare downstream tool names via
    # args.tools so the class can look them up and the graph stays connected.
    "args": { "tools": { "section_writer": "section_writer" } }
}
```

`args.tools` accepts a dict (label → agent name) or a plain list of names. The validator
checks its shape.

Working examples in the studio repo:
`coded_tools/agent_network_instructions_editor/write_all_instructions.py`,
`coded_tools/experimental/copy_cat/copyist.py`,
`coded_tools/experimental/mdap_decomposer/decomposition_solver.py`.

Use `return_exceptions=True` with `asyncio.gather` so one failed branch doesn't abort them all.

---

## Reservations — ephemeral agent networks

With `allow.reservations: true` on the agent spec, `args["reservationist"]` provides an
`AccumulatingAgentReservationist` for creating temporary agent networks at runtime.

```hocon
{
    "name": "DeployGeneratedNetwork",
    "function": { "description": "...", "parameters": { ... } },
    "class": "deploy_network.DeployNetwork",
    "allow": { "reservations": true }
}
```

```python
async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Any:
    reservationist = args.get("reservationist")
    if reservationist is None:
        return "Error: reservations are not enabled for this tool."

    async with reservationist:
        reservation = await reservationist.reserve(lifetime_in_seconds=3600, prefix="generated")
        await reservationist.deploy_one(reservation, network_config, confirmation=True)
        return {"url": reservation.get_url()}
```

Interface: `reserve(lifetime_in_seconds, prefix) -> Reservation`, `deploy(deployment_dict,
confirmation)`, `deploy_one(reservation, deployment, confirmation)`,
`validate_with(external_networks, mcp_servers)`. It is an async context manager; default
lifetime is 24 hours.

`Reservation` exposes `get_reservation_id()`, `get_lifetime_in_seconds()`,
`get_expiration_time_in_seconds()`, `get_url()`.

Undocumented in the upstream HOCON reference — see `registries/agent_network_designer.hocon`
and `neuro_san/registries/copy_cat.hocon` for real usage.

---

## Reading agent network files from a tool

To parse a HOCON network from inside a tool, use the framework's restorer rather than raw
pyhocon — it handles includes and substitutions:

```python
from neuro_san.internals.graph.persistence.agent_network_restorer import AgentNetworkRestorer

restorer = AgentNetworkRestorer(registry_dir="registries")
agent_network = await restorer.async_restore(file_reference="basic/music_nerd.hocon")
config = agent_network.get_config()
```

These are framework internals and may shift between releases — pin your expectations to the
neuro-san version you test against.

---

## MCP client from a coded tool

Needed when the MCP server uses a transport other than streamable HTTP, or when the URL
doesn't match the canonical MCP URI shape.

```python
from langchain_mcp_adapters.client import MultiServerMCPClient


async def async_invoke(self, args: Dict[str, Any], sly_data: Dict[str, Any]) -> Any:
    client = MultiServerMCPClient({
        "bmi": {"url": "http://localhost:8000/mcp/", "transport": "streamable_http"}
    })
    tools = await client.get_tools()
    return await tools[0].ainvoke({"weight": args["weight"], "height": args["height"]})
```
