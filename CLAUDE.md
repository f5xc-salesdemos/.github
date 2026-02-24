# f5xc-salesdemos — Multi-Repository Orchestration

## Teammate Protocol

- Each teammate MUST `cd` into their assigned repository
  before starting work
- After cd'ing, read that repo's CLAUDE.md — it contains
  full ecosystem docs, workflow rules, and CI procedures
- Each subdirectory is an independent git repo — use
  standard git workflow within it
- Never commit changes that span multiple repos in a
  single operation

## GitHub Organization

- **Org**: `f5xc-salesdemos`
- **Total repos**: 21 (7 infrastructure + 14 content)

## Repository Categories

### Infrastructure repos (7 repos, custom workflows)

| Repo | Role | Key Notes |
| ---- | ---- | ---- |
| `docs-control` | Source-of-truth — CI workflows, governance, settings enforcement | Owns 26 managed files synced to all 20 downstream repos |
| `docs-theme` | npm package — Starlight plugin, Astro config, CSS, fonts, layout | Owns `astro.config.mjs`, `config.ts`, `content.config.ts` |
| `docs-builder` | Docker image — build orchestration, npm deps, Puppeteer PDF | Owns `Dockerfile`, `entrypoint.sh`, `package.json` deps |
| `docs-icons` | npm packages — Iconify JSON icon sets, Astro icon components | Dispatches to docs-builder on npm publish |
| `terraform-provider-f5xc` | Custom Go Terraform provider for F5 XC | Super-linter can take 30-60+ min; only required check: `check / Check linked issues` |
| `terraform-provider-mcp` | MCP server exposing Terraform provider schemas | Receives managed files from docs-control |
| `api-mcp` | MCP server for the F5 XC API | Receives managed files from docs-control |

### Content repos (14 repos, managed workflows only)

These repos only contain a `docs/` directory plus managed
files. All CI workflows are synced from docs-control.

`docs` · `administration` · `nginx` · `observability` ·
`was` · `mcn` · `dns` · `cdn` · `bot-standard` ·
`bot-advanced` · `ddos` · `waf` · `api-protection` · `csd`

## Managed Files Constraint

26 files are owned by `docs-control` and synced to all 20
downstream repos via the enforcement workflow. **NEVER edit
managed files in downstream repos** — local changes will be
overwritten on the next enforcement run.

### Managed file categories

- **CI workflows**: `github-pages-deploy.yml`,
  `enforce-repo-settings.yml`, `require-linked-issue.yml`,
  `dependabot-auto-merge.yml`, `super-linter.yml`
- **Templates**: `PULL_REQUEST_TEMPLATE.md`, issue templates
  (`bug_report.md`, `feature_request.md`,
  `documentation.md`, `config.yml`)
- **Governance**: `CONTRIBUTING.md`, `CLAUDE.md`, `LICENSE`
- **Linting/formatting**: `.editorconfig`,
  `.editorconfig-checker.json`, `.yamllint.yaml`,
  `.markdownlint.json`, `biome.json`, `.jscpd.json`,
  `.textlintrc`, `.checkov.yaml`, `zizmor.yaml`,
  `.shellcheckrc`, `.codespellrc`,
  `.pre-commit-config.yaml`
- **Other**: `.gitignore`

### What CAN be edited in downstream repos

- `docs/` content (Markdown/MDX, images, assets)
- Repo-specific source code (Go, TypeScript, etc.)
- Repo-specific config not in the managed list

## Configuration Ownership Rules

| Config | Owner | Change Procedure |
| ---- | ---- | ---- |
| `astro.config.mjs` | docs-theme | PR to docs-theme — copied into Docker image at build time |
| `content.config.ts` | docs-theme | PR to docs-theme — same mechanism |
| Starlight plugins / Astro integrations | docs-theme | Add to `docs-theme/config.ts` |
| npm dependencies (icon packs, libraries) | docs-builder | Add to `docs-builder/package.json` |
| `Dockerfile`, `entrypoint.sh` | docs-builder | PR to docs-builder |
| CI workflows, governance templates | docs-control | PR to docs-control → enforcement sync |
| Icon packages (Iconify JSON, Astro components) | docs-icons | PR to docs-icons → npm publish → dispatch to docs-builder |
| Go Terraform provider source | terraform-provider-f5xc | PR to terraform-provider-f5xc |
| Terraform MCP server | terraform-provider-mcp | PR to terraform-provider-mcp |
| API MCP server | api-mcp | PR to api-mcp |

## Cross-Repo Coordination Patterns

1. **Content change**: edit `docs/` in the content repo →
   CI builds with latest Docker image
2. **Governance change**: PR to docs-control → enforcement
   workflow syncs managed files to all 20 downstream repos
3. **Theme/icon change**: PR to docs-theme or docs-icons →
   semantic release → dispatch to docs-builder → Docker
   rebuild → dispatch to all content repos → Pages rebuild
4. **Terraform provider change**: PR to
   terraform-provider-f5xc — independent CI pipeline,
   receives managed files but not part of docs dispatch
   chain
5. **API MCP change**: PR to api-mcp — independent CI
   pipeline, receives managed files

## Release Dispatch Chain

```
docs-theme/docs-icons merge
  → semantic release (npm publish)
    → dispatch to docs-builder
      → Docker image rebuild
        → dispatch to content repos
          → GitHub Pages rebuild
```

## When to Spawn Teammates

| Situation | Action |
| ---- | ---- |
| Changes touching 2+ repos | One teammate per repo |
| Investigation across repos | Teammates investigate in parallel |
| Single-repo content change | No team needed, work directly |
| Managed file change | Work in docs-control only — sync handles the rest |
| Theme + content change | One teammate for docs-theme, wait for dispatch, then content |

## Key Config Files

- `docs-control/.github/config/downstream-repos.json` —
  list of 20 downstream repos receiving managed files
- `docs-control/.github/config/docs-sites.json` — list of
  19 docs sites for Pages rebuild dispatch
- `docs-control/.github/config/repo-settings.json` —
  managed files list, branch protection, repo settings
