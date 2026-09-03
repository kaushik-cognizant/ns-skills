# External Agents and MCP Reference

---

## External agent networks

Reference another agent network as a tool — same calling protocol as an internal agent.

```hocon
# Local, same server — leading slash
"tools": ["/other_network"]
"tools": ["/basic/music_nerd"]        # category-qualified

# Remote, different server
"tools": ["http://192.168.1.100:8080/other_network"]
```

Validation requires you to declare them, or it reports unknown tool names:

```bash
ns validate registries/my_network.hocon --external-agents '/other_network,/second_network'
```

### Always give an externally-called network a parameter

If a network's front man has no `parameters` and another network calls it, the framework
**synthesizes a required `inquiry` string and logs a warning**. Declare your own instead —
it's clearer and gives you control of the name and description.

### sly_data across the boundary

Nothing crosses a network boundary unless allowed. See `schema.md` for full semantics.

```hocon
"allow": {
    "to_downstream":   { "sly_data": ["api_key"] },
    "from_downstream": { "sly_data": ["result"], "messages": ["/other_network"] }
}
```

`from_downstream.messages` takes the reference **exactly as it appears in `tools`**.

### Flattening a network

`ns internalize-agents` inlines all `/`-prefixed external references and includes into one
self-contained file — useful for shipping or debugging:

```bash
ns internalize-agents registries/my_network.hocon -o /tmp/flat.hocon --search-paths registries
```

---

## Consuming MCP servers

Declared inside an agent's `tools` list, in either of two forms.

### String form

```hocon
"tools": ["https://mcp.deepwiki.com/mcp"]
```

A bare string is treated as MCP **only if it matches the canonical MCP server URI shape**:

- scheme is `http` or `https`
- a host is present
- **no fragment**
- the literal `mcp` appears either as a **hostname label** (`mcp.example.com`) or as **any
  path segment** (`/mcp`, `/mcp/free`, `/server/mcp`, `/v1/mcp/server`)

If your URL doesn't match, it won't be recognized as MCP — use the dict form.

### Dictionary form

Always treated as MCP, and lets you whitelist which tools to expose:

```hocon
"tools": [
    { "url": "https://example.com/api", "tools": ["search", "summarize"] }
]
```

Only **streamable-HTTP** transport is supported. For other transports (stdio, SSE), write a
coded tool using `MultiServerMCPClient` from `langchain-mcp-adapters` — see
`registries/tools/mcp_bmi_streamable_http.hocon` in the studio repo.

> The MCP adapter is explicitly marked experimental upstream; expect this surface to shift.

### Authentication

Two mechanisms. **`sly_data` wins on conflict.**

Per-request, via `sly_data["http_headers"]` keyed by URL:

```python
sly_data = { "http_headers": { "https://example.com/mcp": { "Authorization": "Bearer <token>" } } }
```

Advertise it so a UI can run OAuth and inject the token for you:

```hocon
"function": {
    "description": "...",
    "sly_data_schema": {
        "type": "object",
        "properties": { "http_headers": { "type": "object" } }
    }
}
```

Static, via the file named by `MCP_SERVERS_INFO_FILE`:

```hocon
{
  "https://example.com/mcp": {
    "http_headers": { "Authorization": "Bearer <token>" },
    "tools": ["tool_1", "tool_2"]
  }
}
```

The file's `tools` filter applies **only if** the agent HOCON didn't specify one.

---

## Serving your networks as MCP tools

This is a **manifest-level** setting, not an agent-HOCON one:

```hocon
# registries/manifest.hocon
"my_network.hocon": { "serve": true, "mcp": true }
```

`mcp: true` implies `public: true`. Enable the MCP surface on the server with
`AGENT_MCP_ENABLE` (or `--mcp_enable`), or run MCP-only with `AGENT_MCP_ONLY` /
`--mcp_only`. Protocol is MCP 2025-06-18 over JSON-RPC 2.0 HTTP — not streaming. Each public
network becomes one MCP tool. Full handshake examples: `neuro-san/docs/mcp_service.md`.

Client-side, `agent_cli` can talk to it with the `--mcp` shorthand.
