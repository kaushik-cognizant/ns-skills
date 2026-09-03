# Complete Network Examples

Working networks to adapt. All verified against neuro-san `0.6.98` / studio `0.3.20`.

---

## 1. Minimal single agent

```hocon
{
    include "config/llm_config.hocon"

    "metadata": {
        "description": "A general-purpose assistant.",
        "tags": ["basic"],
        "sample_queries": ["What is the capital of France?"]
    },

    "tools": [
        {
            "name": "Assistant",
            "function": { "description": "A helpful assistant." },
            "instructions": """
You are a helpful assistant. Answer the user's questions clearly and concisely.
"""
        }
    ]
}
```

The front man is identified by having no `parameters` in its `function`.

---

## 2. Hierarchical routing with a coded tool

No AAOSA — the front man routes explicitly. Right choice when responsibilities don't overlap.

```hocon
{
    include "config/llm_config.hocon"

    "metadata": {
        "description": "Customer support router.",
        "tags": ["support"],
        "sample_queries": ["Where is my order?", "How do I reset my password?"]
    },

    "llm_config": { "model_name": "gpt-5.2", "temperature": 0.3 },

    "tools": [
        {
            "name": "SupportRouter",
            "function": { "description": "Routes customer inquiries to the right specialist." },
            "instructions": """
You are a customer support coordinator. Greet the customer, then route their issue:
OrdersExpert for order questions, AccountExpert for account and password questions.
NEVER answer a domain question yourself — always delegate.
""",
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
            "instructions": """
You are an orders specialist. Use OrdersDB to look up order status before answering.
""",
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
            "instructions": """
You are an account specialist. Help customers reset passwords and update profiles.
Never ask for or repeat a password.
"""
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
            "class": "order_lookup.OrderLookup"
        }
    ]
}
```

Place the coded tool at `coded_tools/<network_name>/order_lookup.py`.

---

## 3. AAOSA network — unquoted HOCON style

The other accepted syntax: no quotes on keys, no commas. Both styles are idiomatic.

```hocon
include "registries/aaosa_basic.hocon"
include "registries/expertise_scoping_instructions.hocon"
include "config/llm_config.hocon"

metadata {
    description = "Finds coffee at any time of day."
    tags = ["AAOSA"]
    sample_queries = ["Where can I get coffee right now?"]
}

tools = [
    {
        name = "CoffeeFinder"
        function { description = "Finds coffee at any time of day." }
        instructions = ${expertise_scoping_instructions} """
Your name is CoffeeFinder. Consult all your tools before saying nothing is available.
""" ${aaosa_instructions}
        tools = ["CoffeeShop", "FastFoodChain", "GasStation"]
        structure_formats = "json"
    }
    {
        name = "CoffeeShop"
        function = ${aaosa_call}{ description = "A coffee shop, open 7am to 6pm." }
        instructions = """
Your name is CoffeeShop. You serve good coffee, but only between 7am and 6pm.
""" ${aaosa_instructions}
    }
    {
        name = "FastFoodChain"
        function = ${aaosa_call}{ description = "A fast food chain, open 6am to midnight." }
        instructions = """
Your name is FastFoodChain. You serve mediocre coffee from 6am to midnight.
""" ${aaosa_instructions}
    }
    {
        name = "GasStation"
        function = ${aaosa_call}{ description = "A gas station, open 24 hours." }
        instructions = """
Your name is GasStation. You serve poor coffee, but you are open 24 hours.
""" ${aaosa_instructions}
    }
]
```

Note: no `command` / `${aaosa_command}` anywhere — that is deprecated.

---

## 4. Toolbox tools with a shared instructions prefix

```hocon
{
    include "registries/aaosa_basic.hocon"
    include "registries/expertise_scoping_instructions.hocon"
    include "config/llm_config.hocon"

    "metadata": {
        "description": "Research assistant with web search and document retrieval.",
        "tags": ["research", "tools"],
        "sample_queries": ["Summarize recent arXiv papers on retrieval-augmented generation."]
    },

    "instructions_prefix": """
You are part of a research assistant network.
""" ${expertise_scoping_instructions},

    "tools": [
        {
            "name": "ResearchLead",
            "function": { "description": "Researches topics using web search and papers." },
            "instructions": ${instructions_prefix} """
Your name is ResearchLead. Gather evidence with your tools before answering.
ALWAYS cite the URL of anything you assert.
""" ${aaosa_instructions},
            "tools": ["WebSearch", "FetchPage", "ArxivSearch", "DateTime"]
        },
        { "name": "WebSearch",   "toolbox": "ddgs_search" },
        { "name": "FetchPage",   "toolbox": "web_fetch",       "args": { "max_content_chars": 10000 } },
        { "name": "ArxivSearch", "toolbox": "arxiv_retriever", "args": { "top_k_results": 5 } },
        { "name": "DateTime",    "toolbox": "get_current_date_time" }
    ]
}
```

`ddgs_search` needs no API key, which makes it the best default for examples.

---

## 5. sly_data with boundaries

```hocon
{
    include "config/llm_config.hocon"

    "metadata": { "description": "Music trivia with running cost tracking.", "tags": ["basic"] },

    "tools": [
        {
            "name": "MusicNerd",
            "function": { "description": "Answers questions about music." },
            "instructions": """
You are a music expert. After each answer, call Accountant to record the cost.
""",
            "tools": ["Accountant"],
            "allow": {
                "to_upstream": { "sly_data": { "running_cost": true } },
                "to_tracing":  { "sly_data": ["running_cost"] }
            },
            "structure_formats": "json"
        },
        {
            "name": "Accountant",
            "function": {
                "description": "Records the cost of an answer and returns the running total.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "cost": { "type": "float", "description": "Cost of this answer in dollars." }
                    },
                    "required": ["cost"]
                }
            },
            "class": "accountant.Accountant"
        }
    ]
}
```

Within one network sly_data flows freely; `allow` governs what crosses a network boundary or
reaches the client and tracing.

---

## 6. External agents and MCP

```hocon
{
    include "config/llm_config.hocon"

    "metadata": { "description": "Coordinator that delegates to other networks and an MCP server." },

    "tools": [
        {
            "name": "Coordinator",
            "function": { "description": "Coordinates specialist networks." },
            "instructions": """
You coordinate work across specialist networks. Delegate, then compile the results.
""",
            "tools": [
                "/basic/music_nerd",
                "http://192.168.1.100:8080/remote_network",
                { "url": "https://mcp.deepwiki.com/mcp", "tools": ["ask_question"] }
            ],
            "allow": {
                "to_downstream":   { "sly_data": ["http_headers"] },
                "from_downstream": { "sly_data": ["result"], "messages": ["/basic/music_nerd"] }
            }
        }
    ]
}
```

Validate with:

```bash
ns validate registries/my_net.hocon \
    --external-agents '/basic/music_nerd,http://192.168.1.100:8080/remote_network' \
    --mcp-servers 'https://mcp.deepwiki.com/mcp'
```

---

## 7. Middleware — PII redaction and memory

```hocon
{
    include "config/llm_config.hocon"

    "metadata": { "description": "Assistant with persistent memory and PII redaction." },

    "tools": [
        {
            "name": "MemoryAssistant",
            "function": { "description": "An assistant that remembers across sessions." },
            "instructions": """
You are a helpful assistant with long-term memory. Recall relevant context before answering.
""",
            "middleware": [
                {
                    "class": "middleware.persistent_memory.persistent_memory_middleware.PersistentMemoryMiddleware",
                    "args": { "store": "json_file", "sly_data": true }
                },
                {
                    "class": "langchain.agents.middleware.PIIMiddleware",
                    "args": {
                        "pii_type": "email",
                        "strategy": "redact",
                        "apply_to_input": false,
                        "apply_to_output": true
                    }
                }
            ]
        }
    ]
}
```

Middleware order matters — the first entry is outermost.

---

## 8. Manifest registration

```hocon
# registries/basic/manifest.hocon
{
    "my_network.hocon": true,
    "internal_helper.hocon": { "serve": true, "public": false },
    "exposed_tool.hocon": { "serve": true, "mcp": true },
    "work_in_progress.hocon": false
}
```

```hocon
# registries/manifest.hocon
{
    include "registries/basic/manifest.hocon"
    include "registries/tools/manifest.hocon"
    include "registries/generated/manifest.hocon"
}
```
