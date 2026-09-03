# Archived skills — 2026-05-12

Verbatim copies of the original `ns-skills` skill files as they existed on 2026-05-12
(repo commit `34e9c65`), kept for reference.

## Why they were replaced

These were written against neuro-san ~0.6.x (early) and neuro-san-studio ~0.2.x. By
2026-09-03 the upstream repos had moved roughly 1,600 and 1,079 commits ahead
respectively, to neuro-san `0.6.98` and neuro-san-studio `0.3.20`. Several instructions in
these files no longer work:

- `python -m run` — the root `run.py` was deleted; the entry point is now `ns run`.
- The six `requests_*` HTTP tools and `requests_toolkit` were listed as always available.
  All were removed from the default toolbox and now raise a specific removal error.
- `${aaosa_command}` was documented as required on every AAOSA sub-agent. It is now an
  empty string, having been merged into `${aaosa_instructions}`.
- `toolbox/`, `mcp/`, and `registries/config/llm_config.hocon` all moved.
- `max_iterations` was renamed to `max_steps`.

## Replaced by

`skills/neuro-san-agent-network/` and `skills/neuro-san-coded-tool/`, each restructured
into a lean `SKILL.md` plus a `references/` directory.

## Note on location

This directory deliberately sits outside `skills/`. Both installers glob `skills/*/` and
copy every subdirectory they find into the user's skills directory, so an archive placed
under `skills/` would be shipped to everyone who installs.
