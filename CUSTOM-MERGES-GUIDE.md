# CUSTOM-MERGES-GUIDE.md — Upgrade & merge ritual for this fork

**Authoritative checklist** for every upstream sync into this Chatwoot
fork. Follow it top-to-bottom before, during and after merging
`fazerai/*` (or `chatwoot/upstream/*`) into our `codi-*` branches.
Skipping a step in the past has caused: brand drift back to
`fazer.ai`, lost `Click2Run` → `propriacloud` translations,
out-of-sync `CUSTOM-CHANGELOG.md`, and pre-commit hook surprises on
i18n bare strings.

This file is part of the `CUSTOM-*.md` family — every customization
domain lives in its own file with that prefix. Keep them all
consistent; cross-reference rather than duplicate.

## CUSTOM-* file map

| File                          | Domain                                                                    | Touched by upgrades?               |
| :---------------------------- | :------------------------------------------------------------------------ | :--------------------------------- |
| `CUSTOM-AUTH.md`              | Logto / OmniAuth-OpenID-Connect wiring                                    | Sometimes (omniauth gem bumps)     |
| `CUSTOM-BRANDING.md`          | Branding env vars + branding rake task                                    | Rarely                             |
| `CUSTOM-CADDY.md`             | Caddy reverse-proxy + self-signed TLS for local dev                       | Rarely                             |
| `CUSTOM-CHANGELOG.md`         | Per-commit history + version milestones table                             | **Every commit** — see below       |
| `CUSTOM-CLICK2-RUN.md`        | Legacy Click2Run product context (kept for historical search)             | Never                              |
| `CUSTOM-CLICK2RUN-API.md`     | Legacy Click2Run API endpoint mapping (superseded by CUSTOM-WHATSAPP-API) | Never                              |
| `CUSTOM-DEFAULT-LANGUAGE.md`  | Forced pt_BR locale on new accounts/users                                 | Rarely                             |
| `CUSTOM-FAZER-AI.md`          | Authoritative rebrand mapping (fazer-ai → Própria Cloud)                  | **Every merge** — see below       |
| `CUSTOM-MERGES-GUIDE.md`      | This file — upgrade ritual                                                | Every merge (update if ritual evolves) |
| `CUSTOM-WHATSAPP-API.md`      | Própria Cloud (whatsapp-api) integration spec                             | Sometimes (provider service drift) |

## When this guide kicks in

Trigger any of these:

- "fetch upstream" / "merge upstream" / "sync fork" / "pull fazer-ai"
- A new `vX.Y.Z-fazer-ai.N` tag landed on `fazerai/main`
- Chatwoot core (`chatwoot/upstream`) bumped its release version
- Resolving merge conflicts on a `codi-*` branch
- Cherry-picking a fazer-ai bug fix into our active branch

## The ritual (copy into your todo list)

### 0. Safety net (before doing anything destructive)

```bash
git status --short                       # working tree must be clean
git fetch fazerai --tags
git fetch upstream --tags                # chatwoot core (optional)
git tag codi-pre-upgrade-$(date +%Y-%m-%d)   # rollback anchor
```

The `codi-pre-upgrade-*` tag pattern is established (`codi-pre-upgrade-2026-05-07`,
`codi-pre-upgrade2-2026-05-08`). Use a numeric suffix when more than
one safety tag is taken on the same day.

### 1. Decide: same branch or new branch?

| Situation                                                             | Action                                                              |
| :-------------------------------------------------------------------- | :------------------------------------------------------------------ |
| Upstream has new commits on `fazerai/main` but no new tag             | `git merge fazerai/main` on the current `codi-*` branch             |
| A new `vX.Y.Z-fazer-ai.N+1` tag dropped (same chatwoot core version)  | Create `codi-vX.Y.Z-fazer-ai.N+1`, merge our work onto it           |
| Chatwoot core bumped (e.g. 4.13 → 4.14, fazer-ai retags)              | Create `codi-v4.14.0-fazer-ai.N`, merge our work onto it            |
| Cherry-picking a single fix                                           | Cherry-pick on current branch, no rename                            |

The convention: **branch name reflects the base upstream tag, not the
HEAD commit**. Customizations on top are expected drift.

### 2. Read the rebrand rules BEFORE resolving any conflict

Open `CUSTOM-FAZER-AI.md` first — its translation table is the
authoritative rule for `fazer.ai`, `Click2Run`, `c2r` mentions in
conflict regions. Project memory carries the same rules
(`project_rebrand_mapping.md`); a fresh Claude session loads it
automatically.

Do **not** translate:

- `lib/global_config_service.rb` and other upstream-owned `lib/`
  files (translate strings inside, accept the rest)
- `docker-compose.yaml` / `Dockerfile` references to `click2run/...`
  image names (docker hub namespace)
- `config/features.yml` `channel_whatsapp_click2run` flag (deprecated
  back-compat slot)
- `lib/middleware/fazer_ai_platform_header.rb` filename (renaming
  cascades into `config/application.rb`)
- `.claude/skills/sync-fork/SKILL.md` references to `fazer-ai/chatwoot`
  / `chatwoot-pro` — those are real GitHub org/repo names

### 3. Merge

```bash
# In-place merge:
git merge fazerai/main --no-edit

# OR new-branch flow:
git checkout v4.13.0-fazer-ai.67
git checkout -b codi-v4.13.0-fazer-ai.67
git merge codi-v4.13.0-fazer-ai.66 --no-ff \
  -m "Merge codi-v4.13.0-fazer-ai.66 customizations into codi-v4.13.0-fazer-ai.67"
```

Resolve conflicts using the rebrand mapping. When in doubt, prefer
keeping our customization side and translating any upstream strings
that landed in the resolved hunk.

### 4. Sweep for drift introduced by the merge

```bash
grep -rEn "fazer[._-]?ai|Click2Run|click2run|\\bc2r\\b" \
  app/ config/ lib/ public/brand-assets/ 2>&1 \
  | grep -vE "node_modules|click2run/|\.css$|enterprise/" \
  | head -40
```

Apply the translation table from `CUSTOM-FAZER-AI.md`. Changes go in
their own commit (`chore(brand): ...`).

### 5. Verify the runtime

```bash
docker compose restart rails sidekiq
# Wait for "Listening on http"
docker compose exec -T rails curl -s http://localhost:3000/health
# Expect: {"status":"woot","platform":"propriacloud","version":"4.13.0"}
```

Smoke-test the propriacloud provider stack:

```bash
docker compose exec -T rails bundle exec rails runner '
  ch = Channel::Whatsapp.find_by(provider: "propriacloud")
  puts "service: #{ch.provider_service.class}"
  puts "events subscribed: #{Whatsapp::Providers::WhatsappPropriacloudService::DEFAULT_WEBHOOK_EVENTS.size}"
'
```

If any of these regressed, the merge re-introduced something the
rebrand sweep missed — go back to step 4.

### 6. Update CUSTOM-CHANGELOG.md (mandatory)

Every commit lands in the changelog. Every milestone (new branch,
new tag, new upstream version adopted) lands in the **Version
milestones** table at the top of the doc.

Per-commit refresh:

```bash
git log --all --reverse --pretty=format:'COMMIT %H|%aI|%s' --numstat \
  --author='robson@robson.com.br' > .llm/temporary/our-history.txt
docker compose exec -T rails ruby /app/.codi/scripts/build-changelog.rb \
  .llm/temporary/our-history.txt CUSTOM-CHANGELOG.md
```

Milestones table edit: directly in
`.codi/scripts/build-changelog.rb` (search for `## Version
milestones`). The script preserves the block on regen.

Pre-commit hook will lint the i18n bare-string check; if a merge
landed new untranslated UI strings, add them to
`app/javascript/dashboard/i18n/locale/{en,pt_BR}/*.json` before
committing.

### 7. Tag a release (only when ready to ship)

```bash
git tag codi-v4.13.0-fazer-ai.66.2   # increment the trailing iter
```

Update the milestone table for the new tag (step 6 — milestones).

### 8. Push (only when explicitly asked)

```bash
git push -u origin codi-v4.13.0-fazer-ai.66
git push origin codi-v4.13.0-fazer-ai.66.2   # tags push separately
```

**NEVER** force-push to `main`. **NEVER** push without explicit
user authorization.

## Commit conventions

- Conventional Commits (`type(scope): subject`) — see `AGENTS.md`
  / `CLAUDE.md` for the canonical list.
- **No AI / LLM / Claude attribution** in commits, PR bodies, file
  headers or any in-repo artifact. This is a hard rule, codified in
  project memory (`feedback_no_ai_attribution.md`).
- Local git identity: `Robson Martins <robson@robson.com.br>`
  (already set as `--local` for this repo).

## Recurring drift watchlist

Files that almost always reintroduce `fazer.ai` / `Click2Run`
mentions on upstream merges. Inspect them every time:

- `app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue`
- `app/javascript/dashboard/components/app/UpdateBanner.vue`
- `app/javascript/dashboard/routes/dashboard/kanban/Index.vue`
- `app/javascript/dashboard/routes/dashboard/internalChat/ProFeatureNudge.vue`
- `app/javascript/dashboard/routes/dashboard/settings/account/components/BuildInfo.vue`
- `app/javascript/v3/views/login/Index.vue`
- `app/javascript/dashboard/i18n/locale/{en,pt_BR}/kanban.json`
- `app/javascript/dashboard/constants/globals.js`
- `app/views/super_admin/devise/sessions/new.html.erb`
- `app/controllers/health_controller.rb`
- `lib/middleware/fazer_ai_platform_header.rb`
- `lib/tasks/branding.rake`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` (logo-alt)
- `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` (Click2Run comments)

## Cross-references

- `CUSTOM-FAZER-AI.md` — translation table (Própria Cloud rebrand rules)
- `CUSTOM-CHANGELOG.md` — Version milestones table + per-commit history
- `CUSTOM-WHATSAPP-API.md` — propriacloud provider integration spec
- `CUSTOM-DEFAULT-LANGUAGE.md` — pt_BR-on-creation enforcement
- `CUSTOM-AUTH.md` — Logto / OmniAuth wiring
- `.claude/skills/sync-fork/SKILL.md` — upstream's own merge ritual (chatwoot → fazer-ai → chatwoot-pro)
- `.codi/scripts/build-changelog.rb` — changelog regen helper

## Glossary

- **codi** — internal prefix for our customization branches/tags.
- **propriacloud** — canonical name of our WhatsApp / SSO provider stack.
- **click2run** — legacy provider id retained as a back-compat alias.
- **multicanal.propria.cloud** — the public marketing domain that replaced `fazer.ai` everywhere user-facing.
