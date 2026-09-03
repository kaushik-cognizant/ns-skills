# Testing Coded Tools

Two layers: **unit tests** for the Python class (fast, no LLM), and **integration fixtures**
for the network that uses it (needs API keys).

---

## Unit tests

Use `IsolatedAsyncioTestCase` for async tools. Place at
`tests/coded_tools/<network>/test_my_tool.py`, mirroring the source layout.

```python
from unittest import IsolatedAsyncioTestCase

from coded_tools.my_network.my_tool import MyTool


class TestMyTool(IsolatedAsyncioTestCase):

    async def test_basic_call(self):
        tool = MyTool()
        result = await tool.async_invoke(args={"query": "hello"}, sly_data={})
        self.assertIsInstance(result, dict)
        self.assertIn("result", result)

    async def test_missing_required_arg(self):
        tool = MyTool()
        result = await tool.async_invoke(args={}, sly_data={})
        self.assertIn("Error", result)

    async def test_reads_sly_data(self):
        tool = MyTool()
        result = await tool.async_invoke(args={"query": "x"}, sly_data={"api_key": "test-key"})
        self.assertNotIn("Error", str(result))

    async def test_writes_sly_data(self):
        tool = MyTool()
        sly_data = {}
        await tool.async_invoke(args={"item": "coffee", "quantity": 2}, sly_data=sly_data)
        self.assertIn("cart", sly_data)
        self.assertEqual(sly_data["cart"]["coffee"], 2)

    async def test_hocon_args_override_llm_args(self):
        """HOCON args are merged into the same dict and win on key collision."""
        tool = MyTool()
        result = await tool.async_invoke(args={"query": "x", "limit": 3}, sly_data={})
        self.assertLessEqual(len(result["items"]), 3)
```

### What to cover

- Happy path with the minimum valid args
- Every required arg missing → returns an `"Error: ..."` string, not an exception
- Type coercion — the LLM can send `"5"` where you expect `5`
- sly_data read, and sly_data write if the tool uses the bulletin board
- External calls **mocked** — never hit a live API in a unit test
- Framework-injected keys present in `args` (`origin`, `progress_reporter`) don't break it

### Mocking an HTTP call

```python
from unittest.mock import AsyncMock
from unittest.mock import patch


class TestFetchData(IsolatedAsyncioTestCase):

    async def test_http_error_returns_error_string(self):
        tool = FetchData()
        with patch.object(FetchData, "_fetch", new=AsyncMock(side_effect=TimeoutError)):
            result = await tool.async_invoke(args={"url": "https://x"}, sly_data={})
        self.assertIn("Error", result)
```

### Testing a progress reporter

```python
class FakeProgress:
    def __init__(self):
        self.calls = []

    async def async_report_progress(self, structure, content=""):
        self.calls.append((structure, content))


async def test_reports_progress(self):
    progress = FakeProgress()
    tool = MyTool()
    await tool.async_invoke(args={"query": "x", "progress_reporter": progress}, sly_data={})
    self.assertGreater(len(progress.calls), 0)
```

---

## Running unit tests

```bash
make test-unit
# = pytest tests/ --cov=coded_tools --cov=neuro_san_studio -m "not integration"

pytest tests/coded_tools/my_network/test_my_tool.py -v
pytest tests/ -v -k "my_tool"
```

`make test` runs lint (ruff format, ruff check, pylint, pymarkdown) and then the unit tests.

---

## Integration fixtures

Exercise the tool through a real network. Fixtures are HOCON, under `tests/fixtures/`:

```hocon
{
    "agent": "basic/my_network",
    "timeout_in_seconds": 180,
    "success_ratio": "1/1",
    "interactions": [
        {
            "sly_data": { "api_key": "test-key" },
            "text": """Look up order ORD-123.""",
            "response": {
                "text": { "keywords": ["ORD-123"] },
                "sly_data": { "running_cost": { "greater": 0.0 } }
            }
        }
    ]
}
```

Stock tests: `value`/`not_value`, `less`/`not_less`, `greater`/`not_greater`,
`keywords`/`not_keywords`, `gist`/`not_gist`. Assertable areas: `text`, `sly_data`,
`structure`.

Rules the fixture validator enforces:

- `keywords` are case-sensitive and each should be ≤5 words
- `value` must be a float, not an int, for numeric comparison
- **Never pre-set `running_cost`, `TopicMemory`, or `username`** in fixture `sly_data` —
  the network produces those, and seeding them invalidates the test

### Fixtures are not auto-discovered

Add each to a `@parameterized.expand` list in
`tests/integration/test_integration_test_hocons.py`, or it silently never runs.

```bash
make test-integration
pytest -s -m "integration_basic" --timer-top-n 100
```

---

## Structural checks first

Cheapest signal, no API key needed:

```bash
ns validate registries/basic/my_network.hocon --verbose
```

This catches a `class` path that doesn't resolve to a real module, `parameters` that don't
match what the tool reads, and missing/unreachable nodes — before you spend a live LLM call.
