# Environment Variables for Coded Tools

Read env vars in `__init__` (fails fast, visible at startup) or inside
`async_invoke`/`invoke` (picks up changes per call). Prefer `os.getenv("KEY")` — it returns
`None` — over `os.environ["KEY"]`, which raises `KeyError`.

Use `sly_data` instead of an env var when the secret varies per request, for example a
per-user token injected by the client.

---

## Core framework

| Variable | Default | Purpose |
|---|---|---|
| `AGENT_TOOL_PATH` | `<cwd>/coded_tools` | Root directory for coded tool modules |
| `AGENT_TOOL_PATH_ONLY` | `false` | Restrict class resolution to `AGENT_TOOL_PATH`; fully-qualified paths stop resolving |
| `AGENT_MANIFEST_FILE` | `<cwd>/registries/manifest.hocon` | Which networks are served |
| `AGENT_TOOLBOX_INFO_FILE` | packaged `neuro_san_studio/toolbox/toolbox_info.hocon` | Toolbox config; `""` opts out |
| `MCP_SERVERS_INFO_FILE` | `<cwd>/mcp/mcp_info.hocon` if present, else packaged | MCP server config |
| `AGENT_LLM_INFO_FILE` | none | Extra LLM catalog |

## LLM providers

| Variable | Provider |
|---|---|
| `OPENAI_API_KEY` | OpenAI |
| `ANTHROPIC_API_KEY` | Anthropic |
| `GOOGLE_API_KEY` | Google Gemini |
| `MISTRAL_API_KEY` | Mistral |
| `AZURE_OPENAI_API_KEY` + `AZURE_OPENAI_ENDPOINT` + `OPENAI_API_VERSION` + `AZURE_OPENAI_DEPLOYMENT_NAME` | Azure OpenAI |
| `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` | AWS Bedrock |

Validate with `ns check-llm-keys --tier {1,2,3}`.

## Search and web

| Variable | Default | Used by |
|---|---|---|
| `TAVILY_API_KEY` | none | `tavily_search` |
| `BRAVE_API_KEY` | none | `brave_search` |
| `BRAVE_URL` | `https://api.search.brave.com/res/v1/web/search?q=` | `brave_search` |
| `BRAVE_TIMEOUT` | `30` | `brave_search` |
| `GOOGLE_SEARCH_API_KEY` | none | `google_search` |
| `GOOGLE_SEARCH_CSE_ID` | none | `google_search` custom engine ID |
| `GOOGLE_SEARCH_URL` | `https://www.googleapis.com/customsearch/v1` | `google_search` |
| `GOOGLE_SEARCH_TIMEOUT` | `30` | `google_search` |
| `SERPER_API_KEY` | none | `google_serper` |
| `YDC_API_KEY` | none | You.com search |
| `NYT_API_KEY` | none | New York Times tool |
| `GUARDIAN_API_KEY` | none | Guardian tool |

`ddgs_search` needs no key — the best default when writing examples.

## Databases

| Variable | Purpose |
|---|---|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_HOST` / `POSTGRES_PORT` / `POSTGRES_DB` | PostgreSQL, used by RAG tools |

## Atlassian

| Variable | Purpose |
|---|---|
| `JIRA_USERNAME` | Jira / Confluence username |
| `JIRA_API_TOKEN` | Jira / Confluence API token |
| `JIRA_INSTANCE_URL` | Instance URL |
| `JIRA_CLOUD` | Cloud vs server flag |
| `JIRA_OAUTH2` | OAuth2 JSON, alternative to token auth |

## Enterprise integrations

| Variable | Purpose |
|---|---|
| `SERVICENOW_INSTANCE_URL` / `SERVICENOW_USER` / `SERVICENOW_PWD` | ServiceNow |
| `AGENTFORCE_MY_DOMAIN_URL` / `AGENTFORCE_AGENT_ID` / `AGENTFORCE_CLIENT_ID` / `AGENTFORCE_CLIENT_SECRET` | Salesforce Agentforce |
| `SLACK_BOT_TOKEN` / `SLACK_USER_TOKEN` | Slack |
| `GITHUB_TOKEN` | GitHub |
| `MEM0_API_KEY` / `MEM0_DEFAULT_USER_ID` | Mem0 persistent memory backend |
| `GOOGLE_APPLICATION_CREDENTIALS` | GCP service-account credentials path |
| `GCP_PROJECT_ID` / `GCP_LOCATION` / `ENGINE_ID` | GCP |

## Authorization (optional)

| Variable | Default | Purpose |
|---|---|---|
| `AGENT_AUTHORIZER` | none | Authorizer class; unset skips auth |
| `FGA_API_URL` / `FGA_API_TOKEN` / `FGA_MODEL_ID` | none | OpenFGA |
| `FGA_STORE_NAME` | `default` | OpenFGA store |

## Designer and logging

| Variable | Default | Purpose |
|---|---|---|
| `AGENT_NETWORK_DESIGNER_VERBOSE` | unset | Promotes `AndLogger` INFO logs |
| `LOG_LEVEL` | `info` | Server log level |
| `THINKING_FILE` | `<cwd>/logs/agent_thinking.txt` | Agent reasoning log |

---

## Pattern

```python
import logging
import os

from neuro_san.interfaces.coded_tool import CodedTool

logger = logging.getLogger(__name__)


class MyTool(CodedTool):
    def __init__(self):
        self.api_key = os.getenv("MY_SERVICE_API_KEY")
        if not self.api_key:
            logger.error("MY_SERVICE_API_KEY is not set")

    async def async_invoke(self, args, sly_data):
        # Env var first, per-request sly_data as override
        api_key = sly_data.get("my_service_api_key") or self.api_key
        if not api_key:
            return "Error: MY_SERVICE_API_KEY is not configured."
        ...
```
