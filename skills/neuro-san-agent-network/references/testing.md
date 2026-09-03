# Testing Reference

Agent networks are tested with **data-driven HOCON fixtures**, not hand-written Python.
Full schema: `neuro-san/docs/test_case_hocon_reference.md`.

---

## Fixture shape

Fixtures live under `tests/fixtures/`, mirroring the `registries/` grouping.

```hocon
{
    "agent": "basic/coffee_finder_advanced",
    "timeout_in_seconds": 180,
    "success_ratio": "1/1",
    # "connections": ["direct"],          # restrict to specific connection types
    # "use_direct": true,
    "interactions": [
        {
            "sly_data": { "time": "8 am" },
            "text": """Where can I get coffee?""",
            "response": {
                "text": {
                    "gist": ["""The response should name a coffee shop that is open at 8 am."""]
                }
            }
        }
    ]
}
```

Top-level keys: `agent`, `connections`, `success_ratio`, `use_direct`, `metadata`,
`timeout_in_seconds`, `interactions`.

Per-interaction keys: `text`, `sly_data`, `chat_filter`, `continue_conversation`, `response`.

`success_ratio` like `"1/1"` or `"2/3"` lets a flaky LLM assertion pass on retry.

---

## Stock tests

Assertable areas: `text`, `sly_data` (keyed per sly_data key), and `structure`.

| Test | Meaning |
|---|---|
| `value` / `not_value` | Exact value match. **Must be a float, not an int**, for numeric comparisons |
| `less` / `not_less` | Numeric comparison |
| `greater` / `not_greater` | Numeric comparison |
| `keywords` / `not_keywords` | Substring presence. **Case-sensitive, and each entry should be ≤5 words** |
| `gist` / `not_gist` | LLM-judged semantic match — use for prose |

```hocon
"response": {
    "text": { "keywords": ["order placed"], "not_keywords": ["error"] },
    "sly_data": { "running_cost": { "greater": 0.0 } }
}
```

Rules the fixture validator enforces, worth remembering:

- `keywords` entries are case-sensitive and capped at ~5 words
- `value` must be a float when comparing numbers
- **Never pre-set `running_cost`, `TopicMemory`, or `username` in a fixture's `sly_data`** —
  those are produced by the network, and seeding them invalidates the test

---

## Registering a fixture — the easy thing to miss

**Fixtures are not auto-discovered.** Each one must be added by hand to a
`@parameterized.expand` list in `tests/integration/test_integration_test_hocons.py`:

```python
class TestIntegrationTestHocons(TestCase, FailFastParamMixin):
    DYNAMIC = DynamicHoconUnitTests(__file__, path_to_basis="../fixtures")

    @parameterized.expand(
        DynamicHoconUnitTests.from_hocon_list([
            "basic/job_guessing_skill/bob_job.hocon",
            "basic/my_new_network/my_case.hocon",     # <-- add it here
        ]),
        skip_on_empty=True)
    @pytest.mark.integration
    @pytest.mark.integration_basic
    def test_hocon_basic(self, test_name: str, test_hocon: str):
        self.DYNAMIC.one_test_hocon(self, test_name, test_hocon)
```

Writing the fixture and forgetting this step means the test silently never runs.

`FailFastParamMixin` skips the rest of a group once one case fails — used for multi-turn
conversation groups via `run_hocon_group_fail_fast_case(...)`.

---

## Running tests

```bash
# Unit tests, no LLM
make test-unit
# = pytest tests/ --cov=coded_tools --cov=neuro_san_studio -m "not integration"

# Lint + unit
make test

# Integration (needs API keys)
make test-integration
# = PYTHONPATH=`pwd` AGENT_TOOL_PATH=coded_tools/ \
#   AGENT_MANIFEST_FILE=registries/manifest.hocon pytest -s -m "integration" --timer-top-n 100

# Designer end-to-end (starts a server on port 8080)
make test-designer

# A single marker
pytest -s -m "integration_basic" --timer-top-n 100

# A single fixture — test name is the fixture path with "/" → "_" and ".hocon" stripped
pytest -s ./tests/integration/test_integration_test_hocons.py::TestIntegrationTestHocons::test_hocon_basic_0_basic_my_network_my_case
```

Studio markers (`pytest.ini`): `integration`, `integration_basic`, `integration_industry`,
`integration_experimental`, `integration_agent_network_designer`,
`integration_basic_coffee_finder_advanced`, `integration_basic_music_nerd_pro`,
`integration_industry_airline_policy`, and a few more.

neuro-san core uses a different set: `needs_server`, `integration`, `smoke`, `ollama`,
`non_default_llm_provider`, and variants.

---

## Generating fixtures

The `agent_network_test_generator` network writes fixtures for an existing network
automatically. Its coded tools are `read_agent_network`, `validate_test_fixture`, and
`persist_test_fixture`. See `neuro-san-studio/docs/agent_network_test_generator.md`.

---

## Pre-test structural checks

Always cheaper than a live run, and needs no API key:

```bash
ns validate registries/basic/my_network.hocon --verbose
ns check-config registries/basic/my_network.hocon
```

There is also an LLM-as-judge assessor for grading responses:

```bash
python -m neuro_san.test.assessor.assessor --test_hocon <fixture> --assessor_agent <agent>
```
