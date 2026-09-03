# AAOSA Protocol Reference

AAOSA (Adaptive Agent Oriented Software Architecture) is the standard multi-agent
coordination protocol in neuro-san. Agents self-declare relevance for an inquiry instead of
the front man hard-coding routing.

---

## The single most important change

**`${aaosa_command}` is deprecated.** It was merged into `${aaosa_instructions}` and is now
literally an empty string, kept only so old networks don't break:

```hocon
# Deprecated: aaosa_command has been merged into aaosa_instructions above.
# Kept as an empty string for backward compatibility.
aaosa_command = ""
```

**Do not add `"command": ${aaosa_command}` to new networks.** It does nothing. Sub-agents now
need only `${aaosa_call}` on `function` and `${aaosa_instructions}` appended to `instructions`.

---

## When to use AAOSA

Use it when:

- You have **3 or more sub-agents** with overlapping or ambiguous responsibilities
- The right handler depends on context (time of day, phrasing, domain)
- Sub-agents can each handle **part of** a compound inquiry
- You want agents to self-declare relevance rather than the front man deciding up front

Skip it when:

- You have 1–2 clearly distinct tools — call them directly
- Routing is deterministic and non-overlapping — tool descriptions suffice
- Latency matters — AAOSA adds a Determine round-trip before Fulfill

---

## How it works

```
User → FrontMan
         ├─→ AgentA (mode: Determine) → {Relevant: Yes, Strength: 8, Claim: All}
         ├─→ AgentB (mode: Determine) → {Relevant: Yes, Strength: 5, Claim: Partial}
         └─→ AgentC (mode: Determine) → {Relevant: No,  Strength: 1, Claim: None}

FrontMan picks the strongest claim, plus partial claimants if needed:
         ├─→ AgentA (mode: Fulfill)   → final response
         └─→ AgentB (mode: Follow up) → partial response

FrontMan compiles → User
```

Three modes: **`Determine`** ("can you handle this?"), **`Fulfill`** ("handle it"),
**`Follow up`** ("here's the extra info you asked for").

When there is **no** `mode` parameter, the inquiry came from a human — the agent answers
naturally instead of emitting a protocol block.

---

## The variants

### `aaosa_basic.hocon` — recommended default

Plain-text `[AAOSA]` response block. Cheaper and, per the studio docs, "more refined and
produces more reliable results in practice."

```
[AAOSA]
Name: <your name>
Inquiry: <the inquiry>
Mode: <Determine | Follow up | Fulfill>
Relevant: <Yes | No>
Strength: <number between 1 and 10 representing how certain you are in your claim>
Claim: <All | Partial | None>
Requirements: <None | list of requirements>
Response: <Your response>
```

```hocon
include "registries/aaosa_basic.hocon"
```

### `aaosa.hocon` — strict JSON response

Same routing logic, but sub-agents return JSON. Use when a parent needs to parse claims
programmatically. Still the most-used variant in the studio repo by raw count.

Determine response:
```json
{ "Name": "...", "Inquiry": "...", "Mode": "Determine",
  "Relevant": "Yes", "Strength": 8, "Claim": "All", "Requirements": "None" }
```
Fulfill / Follow up response:
```json
{ "Name": "...", "Inquiry": "...", "Mode": "Fulfill", "Response": "..." }
```

```hocon
include "registries/aaosa.hocon"
```

### `aaosa_basic_debug.hocon` — development only

Includes `aaosa_basic.hocon` and appends a `[DEBUG]` section asking agents to report errors,
exceptions, ambiguities, and prompt-improvement suggestions.

```hocon
include "registries/aaosa_basic_debug.hocon"
```

Switch back to `aaosa_basic.hocon` before production.

### Custom instructions

Override `aaosa_instructions` inline to tailor routing. Always reference the three modes, or
sub-agents won't understand the `mode` parameter.

---

## Companion: expertise scoping

Not AAOSA-specific, but used alongside it in 82 studio networks:

```hocon
include "registries/expertise_scoping_instructions.hocon"
```

Provides `${expertise_scoping_instructions}`:

> Only answer inquiries that are directly within your area of expertise. Do not try to help
> for other matters. Do not mention what you can NOT do. Only mention what you can do.

---

## Wiring

| Variable | Goes on | Purpose |
|---|---|---|
| `${aaosa_instructions}` | **All** AAOSA participants, appended to `instructions` | How to route and how to format by mode |
| `${aaosa_call}` | **Sub-agents only**, as `function` | Supplies the `inquiry` + `mode` parameters |
| `${aaosa_command}` | **Nobody** | Deprecated, empty |

### Standard pattern

```hocon
{
    include "registries/aaosa_basic.hocon"
    include "registries/expertise_scoping_instructions.hocon"
    include "config/llm_config.hocon"

    "instructions_prefix": """
You are part of a customer support assistant network.
""" ${expertise_scoping_instructions},

    "tools": [
        {
            # Front man: plain function, no aaosa_call
            "name": "SupportLead",
            "function": { "description": "Handles user inquiries about support." },
            "instructions": ${instructions_prefix} """
Your name is SupportLead. Coordinate with your specialists.
Never express irrelevance until you have consulted all your tools.
""" ${aaosa_instructions},
            "tools": ["OrdersExpert", "AccountExpert", "BillingExpert"]
        },
        {
            # Sub-agent: aaosa_call merged with a description override
            "name": "OrdersExpert",
            "function": ${aaosa_call} { "description": "Handles order tracking, returns, shipping." },
            "instructions": ${instructions_prefix} """
Your name is OrdersExpert. You handle everything about orders.
""" ${aaosa_instructions}
        },
        {
            "name": "AccountExpert",
            "function": ${aaosa_call} { "description": "Handles passwords, profile, login." },
            "instructions": ${instructions_prefix} """
Your name is AccountExpert.
""" ${aaosa_instructions},
            "tools": ["AccountDB"]
        },
        {
            "name": "BillingExpert",
            "function": ${aaosa_call} { "description": "Handles invoices and payments." },
            "instructions": ${instructions_prefix} """
Your name is BillingExpert.
""" ${aaosa_instructions}
        },
        {
            # Leaf coded tool: NOT an AAOSA participant, no aaosa fields at all
            "name": "AccountDB",
            "function": {
                "description": "Look up an account by ID.",
                "parameters": {
                    "type": "object",
                    "properties": { "account_id": { "type": "string", "description": "Account ID." } },
                    "required": ["account_id"]
                }
            },
            "class": "account_lookup.AccountLookup"
        }
    ]
}
```

### Embedded sub-network front man

When the network itself will sit inside a larger AAOSA hierarchy as an external agent, give
its front man the merged form so it can receive `Determine`/`Fulfill` calls:

```hocon
{
    "name": "network_lead",
    "function": ${aaosa_call} { "description": "An assistant that answers user inquiries." },
    "instructions": ${instructions_prefix} """...""" ${aaosa_instructions},
    "tools": ["SubAgentA", "SubAgentB"]
}
```

Note this gives the front man `parameters`, which normally marks an agent as *not* the front
man. It still works because front-man status is positional for the top-level entry, and this
shape is what the Agent Network Designer emits — but prefer the plain form unless the network
really is being embedded.

---

## Pitfalls

| Mistake | Fix |
|---|---|
| Adding `"command": ${aaosa_command}` | Deprecated and empty — delete it |
| Front man has `${aaosa_call}` unnecessarily | Use a plain `function` unless the network is embedded in a parent hierarchy |
| `${aaosa_instructions}` missing from a sub-agent | It won't understand `Determine`/`Fulfill` and will answer as if from a human |
| Mixing `aaosa.hocon` and `aaosa_basic.hocon` | They define the same names — pick one |
| Putting AAOSA fields on a coded tool | Coded tools are leaves; they never speak AAOSA |
| Custom instructions omitting the three modes | Sub-agents can't interpret `mode` |
| Substitution inside a quoted string | `"text ${aaosa_instructions}"` won't expand — concatenate outside the quotes |
