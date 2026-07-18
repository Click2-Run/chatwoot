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
# NOTE the --multiple flag. `git fetch fazerai upstream origin --tags` is WRONG:
# git reads the trailing names as REFSPECS of the first remote and dies with
# "fatal: couldn't find remote ref upstream".
git fetch --multiple fazerai upstream origin --tags

git tag codi-pre-upgrade-$(date +%Y-%m-%d)   # rollback anchor
```

**All Ruby runs through docker.** There is no `ruby`/`bundle` on the host
PATH in this environment — every Ruby command in this guide must be prefixed:

```bash
docker compose exec -T rails bundle exec <rspec|rails|rubocop> ...
docker compose exec -T rails ruby -c <file.rb>          # syntax check
```

**JS tests run in the `vite` container**, not on the host — the host
`node_modules/` is stale and vitest dies with
`Cannot find module '@rollup/plugin-yaml'`. `npx eslint` *does* work on the
host.

```bash
docker compose exec -T vite npx vitest run <spec files>
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

#### Picking the target tag

```bash
git tag --list 'v*fazer-ai*' --sort=-creatordate | head -5   # newest first
git rev-parse v4.15.1-fazer-ai.88^{commit}; git rev-parse fazerai/main
```

- **Several tags can land between upgrades.** In the `.86 → .88` upgrade both
  `.87` and `.88` were waiting. Merge **only the newest** — the tags are
  cumulative points on the same `main` line, so `.88` already contains `.87`.
  Name the branch after the tag you actually merged.
- **Prefer the tag over `fazerai/main`** — but check whether they are the same
  commit. When the newest tag == `fazerai/main` HEAD (as in `.88`) there is no
  difference. When `main` is *ahead* of the newest tag, those extra commits are
  unreleased; take the tag unless you specifically want them.
- **fazer-ai lags chatwoot core, and that is normal.** At the `.88` upgrade,
  chatwoot core had already tagged `v4.16.0` while fazer-ai was still on
  `4.15.1`. **A new core release is NOT our trigger** — we follow fazer-ai's
  tags. Do not try to pull `chatwoot/upstream` core releases in directly.

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

#### 4a. Semantic drift — what the grep sweep CANNOT catch

The sweep above finds *strings*. The more dangerous class is upstream prose or
UI that is **factually true for fazer-ai and false for us**, in files that
merge cleanly with no conflict. Grep will not flag it, because the words are
supposed to be there. Check these by hand every upgrade:

**1. `AGENTS.md` — our agent memory, and upstream edits it.**
`CLAUDE.md` is a **symlink** to `AGENTS.md`, so whatever upstream writes there
is loaded as authoritative directive memory by every future agent session.

The `.88` merge cleanly imported a `## Git Remotes & PRs` section stating
`origin` → `fazer-ai/chatwoot` plus a runnable
`gh repo set-default fazer-ai/chatwoot`. For **this** clone `origin` is
`Click2-Run/chatwoot`; following that text would open PRs — publishing our
diff — on a repository we do not control. **This is a disclosure risk, not a
broken command.** Our corrected section is now marked `KC` in-file.

```bash
git diff HEAD -- AGENTS.md .claude/   # ALWAYS read this diff in full
git remote -v                         # ground truth to check the prose against
```

**KC (keep-ours) list — re-assert these after every merge:**

| File / section | Why |
| :--- | :--- |
| `AGENTS.md` → "Fork context — read this first" | Points at the `CUSTOM-*.md` family; upstream has no such section |
| `AGENTS.md` → "Git Remotes & PRs" | Upstream's version names the wrong repos (see above) |
| `.claude/skills/sync-fork/SKILL.md` | **Exempt — leave upstream's text alone.** It documents fazer-ai's own chatwoot→fazer-ai→pro flow and its org names are real. Our flow is *this* guide. |

**2. Provider-gated UI.** Upstream ships features for the `baileys` provider;
our inboxes run `propriacloud`. A new CTA whose backend rejects non-baileys
with 422 will still render for our users unless gated. In `.88`, upstream's
"import an already-linked session" CTA had `v-if="connection !== 'open'"`; it
needed `v-if="!isPropriacloud && connection !== 'open'"`. Grep found nothing —
the bug was an *absent* condition.

After any upstream WhatsApp feature, ask: *does this reach a propriacloud
inbox, and does the backend actually support it there?*

```bash
# find the provider guard the backend applies, then mirror it in the UI
grep -rn "provider == '" app/controllers app/models app/services | grep -i whatsapp
```

**3. External branded URLs.** New upstream links may point at fazer-ai-owned
properties (`.88` added a `fazerai-whatsapp-connecto` Chrome Web Store link).
**Do not string-replace these** — the slug/extension ID is a live external
identifier and rewriting it yields a dead link. Decide per case: accept,
suppress, or publish our own. Record the decision in `CUSTOM-FAZER-AI.md`
under "Areas explicitly NOT translated" so later sweeps stop re-flagging it.

### 4b. Run migrations the merge brought in (and revert the local-DB artifacts)

Upstream tags routinely ship migrations. Run them, or the app boots against a
stale schema and specs fail in confusing ways.

```bash
docker compose exec -T rails bundle exec rails db:migrate:status | grep '^ *down'
docker compose exec -T rails bundle exec rails db:migrate
```

⚠️ **These two false diffs regenerate on this dev box.** Inspect and revert
them — do not commit either:

| False diff | Why it appears | Action |
| :--- | :--- | :--- |
| `db/schema.rb` — the `index_channel_whatsapp_provider_connection` `where:` clause reformats (`ANY ((ARRAY[…])::text[])` ↔ `ANY (ARRAY[(…)::text, …])`) | The local PostgreSQL renders the same predicate differently than the box that generated the committed schema. **Semantically identical.** | `git checkout -- db/schema.rb` |
| `app/models/conversation.rb` — annotation block loses `kanban_task_id`, its index and its FK | The annotator rewrites from the **live dev DB**, which has no kanban tables (kanban lives on `chatwoot-pro-main`). It deletes annotations for columns this DB lacks. | `git checkout -- app/models/conversation.rb` |

**They come back.** Not just on `db:migrate` — *any* rails invocation
re-triggers them, including a read-only `rails runner` used to smoke-test.
So this is not a one-time cleanup: re-check `git status` after **every**
rails command, and always immediately before committing or tagging.

```bash
git diff --stat                       # expect ONLY the two above
git checkout -- db/schema.rb app/models/conversation.rb
grep -c propriacloud db/schema.rb     # MUST still be >= 1 (our provider index)
git status --short                    # MUST be empty before commit/tag/push
```

The upstream tag normally already contains the correctly regenerated
`schema.rb`, so reverting loses nothing — verify the new tables/FKs are present
in the committed file rather than regenerating them locally:

```bash
grep -n 'add_foreign_key "internal_chat' db/schema.rb   # example from .88
```

### 5. Verify the runtime

```bash
docker compose restart rails sidekiq vite
# Wait for "Listening on http"
#
# Restart ALL THREE, not just rails. Every service bind-mounts the repo
# (`./:/app`), so a long-running container keeps serving stale in-memory
# classes while the files change underneath it. In the .88 upgrade sidekiq
# had been up 2 weeks; the moment the merge hit the working tree it started
# throwing, on every scheduled job:
#
#   NoMethodError: undefined method 'jid=' for an instance of <SomeJob>
#
# That is a stale-process symptom, NOT a regression in the merge — a plain
# `docker compose restart sidekiq` clears it. Confirm recovery by watching
# for start/done pairs rather than assuming:
#   docker compose logs --since 2m sidekiq | grep -E "INFO: (start|done)"
docker compose exec -T rails curl -s http://localhost:3000/health
# Expect: {"status":"woot","platform":"propriacloud","version":"<VERSION_CW>"}
# `platform` MUST be "propriacloud" — "fazer.ai" here means the rebrand sweep
# missed lib/middleware/fazer_ai_platform_header.rb or health_controller.rb.
# `version` tracks VERSION_CW (4.15.1 at the .88 upgrade), NOT the fazer-ai
# tag number.
```

#### Run the specs covering what the merge touched

```bash
docker compose exec -T rails bundle exec rspec $(git diff --name-only HEAD | grep '^spec/' | tr '\n' ' ')
```

**Known-failing baseline — do NOT chase these.** They fail identically on the
previous codi branch; they are our customizations diverging from upstream's
English-assuming specs, not merge regressions:

| Spec | Failure | Cause |
| :--- | :--- | :--- |
| `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb` "deletes inbox" | expects `"Your inbox deletion request will be processed in some time."`, gets the pt_BR string | `User#set_default_ui_locale` (`before_create`) forces `pt_BR` on every user incl. spec fixtures — see `CUSTOM-DEFAULT-LANGUAGE.md` |

Before blaming the merge for ANY spec failure, prove it is new:

```bash
git diff HEAD -- <spec_file>                  # did the merge even touch it?
git show HEAD:<spec_file> | sed -n 'N,Mp'     # was the assertion already there?
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

**⚠️ Do NOT run `build-changelog.rb` against `CUSTOM-CHANGELOG.md`. Edit the
changelog by hand.**

The regen is **destructive**, contrary to what this guide used to claim:

- It **overwrites the Version milestones table** with the copy embedded in
  `.codi/scripts/build-changelog.rb`, which has drifted and is missing rows
  (the `2026-05-11` and `2026-05-14` entries, and the bolded core-version
  bumps). It does *not* "preserve the block".
- It **replaces the hand-written per-release narrative** — the paragraphs
  explaining *why* each conflict was resolved the way it was — with
  auto-generated `path +N/-M` file-stat lists. Running it in the `.88`
  upgrade rewrote 453 lines and destroyed the entire `.86`, `.74` and WABA
  write-ups before being reverted.

That narrative is the actual value of this file: it is where "why is this
line like that?" gets answered on the next upgrade. Machine-generated file
stats are already in `git log`.

So, by hand:

1. Add a row to the **Version milestones** table (move `**Current branch.**`
   off the previous row).
2. Append the safety tag to the rollback-anchors line beneath it.
3. Add a `### YYYY-MM-DD (…)` section under the month heading — one bullet
   per commit, explaining decisions and rationale, not file lists.
4. Mirror the new milestone row into the table inside
   `.codi/scripts/build-changelog.rb`, so the script's copy stops drifting
   further if anyone ever repairs the regen path.

If the regen is ever fixed to merge rather than overwrite, update this step.

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
