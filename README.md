# ns-skills

Claude skill files for neuro-san development.

Currently tracking **neuro-san `0.6.98`** and **neuro-san-studio `0.3.20`**.

## Available skills

- **[neuro-san-agent-network](skills/neuro-san-agent-network/SKILL.md)** — Create, design, validate, and debug HOCON agent networks for the neuro-san framework.
- **[neuro-san-coded-tool](skills/neuro-san-coded-tool/SKILL.md)** — Author Python coded tools that plug into neuro-san agent networks.

Each skill is a lean `SKILL.md` plus a `references/` directory. The `SKILL.md` carries the
core schema and decision rules and loads on every invocation; the reference files hold the
long catalogs (model lists, toolbox tables, environment variables, worked examples) and are
read only when needed, which keeps context cost low.

```
skills/
├── neuro-san-agent-network/
│   ├── SKILL.md
│   └── references/
│       ├── schema.md          # every top-level and per-agent key, the allow block
│       ├── aaosa.md           # AAOSA protocol and its variants
│       ├── llm-config.md      # providers, model names, fallbacks, reasoning
│       ├── toolbox.md         # prebuilt tool catalog, registering new tools
│       ├── mcp-external.md    # external agent networks and MCP servers
│       ├── middleware.md      # middleware, Agent Skills, persistent memory
│       ├── operations.md      # ns CLI, validation, environment variables
│       ├── testing.md         # test fixtures and how to run them
│       └── examples.md        # complete working networks
└── neuro-san-coded-tool/
    ├── SKILL.md
    └── references/
        ├── patterns.md              # templates, args, sly_data, returns, logging
        ├── toolbox-registration.md  # making a tool reusable across networks
        ├── advanced.md              # calling agents, progress, reservations
        ├── testing.md               # unit tests and integration fixtures
        └── env-vars.md              # environment variable catalog
```

## Archive

Previous versions of the skills are kept under [`archive/`](archive/) for reference. They are
deliberately outside `skills/` — the installers copy every subdirectory of `skills/`, so an
archive placed there would be installed alongside the live skills.

## Quick install

### macOS / Linux / WSL / Git Bash

```bash
# Global (~/.claude/skills) — available in every project
curl -fsSL https://raw.githubusercontent.com/kaushik-cognizant/ns-skills/main/install.sh | bash

# Local (./.claude/skills) — only for the current project
curl -fsSL https://raw.githubusercontent.com/kaushik-cognizant/ns-skills/main/install.sh | bash -s -- --local
```

### Windows (PowerShell 5.1+)

```powershell
# Global (~\.claude\skills)
irm https://raw.githubusercontent.com/kaushik-cognizant/ns-skills/main/install.ps1 | iex

# Local (.\.claude\skills) — set SCOPE before piping
$env:SCOPE='local'; irm https://raw.githubusercontent.com/kaushik-cognizant/ns-skills/main/install.ps1 | iex
```

After installing, restart Claude Code and run `/help` to confirm `neuro-san-agent-network` and `neuro-san-coded-tool` appear in the skills list.

## Installer options

Both installers accept the same options.

| Option       | Bash flag / env var                  | PowerShell param / env var          | Default                          |
|--------------|--------------------------------------|--------------------------------------|----------------------------------|
| Scope        | `--global` / `--local`, `SCOPE`      | `-Scope global|local`, `$env:SCOPE` | `global`                         |
| Source repo  | `--repo OWNER/REPO`, `NS_SKILLS_REPO`| `-Repo`, `$env:NS_SKILLS_REPO`      | `kaushik-cognizant/ns-skills`    |
| Branch       | `--branch BRANCH`, `NS_SKILLS_BRANCH`| `-Branch`, `$env:NS_SKILLS_BRANCH`  | `main`                           |

Install locations:

- **Global** — `~/.claude/skills/` (macOS/Linux) or `~\.claude\skills\` (Windows). Available in every Claude Code session.
- **Local** — `./.claude/skills/` in the current directory. Available only when Claude Code runs from that project.

## Manual install

If you'd rather not run a script, clone the repo and copy (or symlink) the skill directories yourself:

```bash
git clone https://github.com/kaushik-cognizant/ns-skills.git
mkdir -p ~/.claude/skills
cp -R ns-skills/skills/neuro-san-agent-network ~/.claude/skills/
cp -R ns-skills/skills/neuro-san-coded-tool   ~/.claude/skills/
```

Use `ln -s` instead of `cp -R` if you want `git pull` updates to flow through automatically.

## Updating

Re-run the installer — it overwrites the existing skill directories in place.

## Uninstalling

```bash
# Global
rm -rf ~/.claude/skills/neuro-san-agent-network ~/.claude/skills/neuro-san-coded-tool

# Local
rm -rf ./.claude/skills/neuro-san-agent-network ./.claude/skills/neuro-san-coded-tool
```

```powershell
# Windows global
Remove-Item -Recurse -Force ~\.claude\skills\neuro-san-agent-network, ~\.claude\skills\neuro-san-coded-tool
```
