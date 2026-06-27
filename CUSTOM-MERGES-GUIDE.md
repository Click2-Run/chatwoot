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

**Commit EVERYTHING first.** The working tree MUST be clean before you
branch or merge. Any in-flight work is committed as a checkpoint on the
*current* `codi-*` branch — split into atomic commits by logical change
(`type(scope): subject`, no AI attribution). This preserves the work,
carries it into the merge, and makes the safety tag a true rollback
point. Do not stash-and-forget; commit.

```bash
git add <files>                          # stage by logical change (not `git add .`)
git commit -m "type(scope): ..."         # one commit per logical change
git status --short                       # MUST now be empty

# "Bring all" — never trust a stale local view of what "latest" is.
git fetch fazerai upstream origin --tags

git tag codi-pre-upgrade-$(date +%Y-%m-%d)   # rollback anchor
```

The `codi-pre-upgrade-*` tag pattern is established (`codi-pre-upgrade-2026-05-07`,
`codi-pre-upgrade2-2026-05-08`). Use a numeric suffix when more than
one safety tag is taken on the same day.

### 1. Decide: same branch or new branch?

| Situation                                                             | Action                                                                                |
| :-------------------------------------------------------------------- | :------------------------------------------------------------------------------------ |
| Upstream has new commits on `fazerai/main` but no new tag             | `git merge fazerai/main` on the current `codi-*` branch                               |
| A new `vX.Y.Z-fazer-ai.N+1` tag dropped (same chatwoot core version)  | New branch `codi-vX.Y.Z-fazer-ai.N+1` cut **FROM the current `codi-*`**, then merge the new tag in |
| Chatwoot core bumped (e.g. 4.14 → 4.15, fazer-ai retags)              | New branch `codi-v4.15.x-fazer-ai.N` cut **FROM the current `codi-*`**, then merge the new tag in  |
| Cherry-picking a single fix                                           | Cherry-pick on current branch, no rename                                             |

#### Direction — do NOT get this backwards (this caused confusion before)

The new branch is cut **FROM our current `codi-*` branch**, and the
**new upstream tag is merged INTO it**. The branch is *named* after the
new upstream tag, but it is *based on* our previous codi branch — never
the reverse.

- **HEAD / ours**  = our codi branch (the new `codi-vNEW`, cut from the old codi)
- **MERGE_HEAD / theirs** = the new upstream tag `vX.Y.Z-fazer-ai.N`

This keeps our customization history as the `--first-parent` mainline
("what's ours" stays answerable), matching the `sync-fork` skill's
stated preference. The branch name reflects the new upstream tag;
customizations on top are expected drift.

> Historical note: upgrades **through `.74`** were done the other way
> (base = upstream tag, merging our codi *in* — e.g. commit
> `312e114525` "Merge codi-v4.13.0-fazer-ai.66 customizations into
> codi-v4.14.0-fazer-ai.74"). **From `.86` onward we standardize on
> base = our codi**, per this section. Don't be misled by the old merge
> commit messages.

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
# In-place merge (untagged upstream commits, stay on the same branch):
git merge fazerai/main --no-edit

# Tagged upgrade — new-branch flow (base = OUR codi, merge the new tag IN):
git checkout codi-v4.14.0-fazer-ai.74           # current codi = base
git checkout -b codi-v4.15.1-fazer-ai.86        # new branch, named for the new upstream tag
git merge v4.15.1-fazer-ai.86 --no-ff \
  -m "Merge upstream v4.15.1-fazer-ai.86 into codi-v4.15.1-fazer-ai.86"
```

In the new-branch flow HEAD is **our** codi branch and `MERGE_HEAD` is
the **upstream tag**. Keep this straight when applying the `sync-fork`
KC/AI/CO/DEL framework: **AI = accept the upstream tag**, **KC = keep
our customization**.

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
