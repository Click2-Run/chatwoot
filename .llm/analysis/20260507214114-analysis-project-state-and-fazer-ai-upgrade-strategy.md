---
Created: 2026-05-07T21:41:14Z
Operation: Comprehensive project-state audit and upgrade-strategy analysis for the Click2Run/fazer-ai/Chatwoot fork
Context: Reintroduce assistant context to the project, surface drift since the last fazer-ai merge, identify the Click2Run customization surface, the in-progress dirty working tree, and lay out a safe path to upgrade to current fazer-ai while preserving local work and aligning with the new Propria.Cloud whatsapp-api product
Related Files:
  - /root/data/development/controledigital/chatwoot.git/AGENTS.md
  - /root/data/development/controledigital/chatwoot.git/CUSTOM_FAZER-AI.md
  - /root/data/development/controledigital/chatwoot.git/CUSTOM_AUTH.md
  - /root/data/development/controledigital/chatwoot.git/CUSTOM_CADDY.md
  - /root/data/development/controledigital/chatwoot.git/CUSTOM_BRANDING.md
  - /root/data/development/controledigital/chatwoot.git/CUSTOM_CLICK2-RUN.md
  - /root/data/development/controledigital/chatwoot.git/CUSTOM_CLICK2RUN-API.md
  - /root/data/development/controledigital/chatwoot.git/CUSTOM_WHATSAPP-QRCODE.md
  - /root/data/development/controledigital/chatwoot.git/.codi/CLICK2RUN_OPENID_INTEGRATION.md
  - /root/data/development/controledigital/chatwoot.git/.codi/CLICK2RUN_OPENID_SETUP.md
  - /root/data/development/controledigital/chatwoot.git/.codi/WHATSAPP_INTEGRATION.md
  - /root/data/development/controledigital/chatwoot.git/.codi/WHATSMEOW_INTEGRATION.md
  - /root/data/development/controledigital/whatsapp-api.git.worktrees/develop/docs/openapi.yaml
---

# Analysis — Project State & Fazer-AI Upgrade Strategy

## 1. Executive Summary

The project is a **three-layer Chatwoot fork** maintained at `/root/data/development/controledigital/chatwoot.git`:

```
upstream/chatwoot/develop  (Chatwoot OSS — chatwoot/chatwoot)
        ↑ merged into
fazerai/main               (Fazer.AI fork — fazer-ai/chatwoot)
        ↑ rebased/merged into
codi-v4.7.0-fazer-ai.6     (Click2Run/codi customizations — Click2-Run/chatwoot)
```

**Active branch**: `codi-v4.7.0-fazer-ai.6` (HEAD: `735c745c8a`).

**Position**:
- Last absorbed fazer-ai release: **`v4.7.0-fazer-ai.6`** (Nov 6 2025).
- Latest available on `fazerai` remote: **`v4.9.0-fazer-ai.13`** (and intermediates `v4.7.0-fazer-ai.7`, `v4.8.0-fazer-ai.{1..7}`, `v4.9.0-fazer-ai.{1..13}`).
- We are roughly **20 tagged releases behind** fazer-ai — about 6 months of upstream activity.

**Working tree state — DIRTY**:
- 4 modified tracked files
- 906 untracked files (mix of: Click2Run docs/CUSTOM_*.md, ~435 source files that match `v4.9.0-fazer-ai.13` and ~471 source files that look like remnants from a prior partial sync).
- 1 stash on `codi-logto`.
- A second worktree at `chatwoot.git.worktrees/develop` checked out at branch `develop`, with **4,065 changed paths** — clearly an in-progress upgrade attempt that was never finished or committed.

**Critical risk to address before any upgrade**: the dirty state must be triaged and a safe restore point established (commit, branch, or tag) before pulling fazer-ai. Current state cannot be cleanly reasoned about because what is "ours" and what is "stale partial-merge debris" overlaps in the working tree.

**New strategic input from this session**: the user's WhatsApp gateway has graduated into a separate first-class product — `whatsapp-api.git` (Go, whatsmeow-based, OpenAPI 3.1, multi-tenant, branded **"Propria.Cloud Solution by Controle Digital"**). The Click2Run WhatsApp provider in this Chatwoot fork must eventually be re-pointed at that API (out of scope for the upgrade itself, but constrains design choices made during it).

---

## 2. Repository Topology

### 2.1 Remotes
```
fazerai  → https://github.com/fazer-ai/chatwoot.git (fetch only, no_push)
origin   → https://github.com/Click2-Run/chatwoot.git (fetch + push)
upstream → https://github.com/chatwoot/chatwoot.git (fetch only, no_push)
```

### 2.2 Local branches (purpose inferred from commits)
| Branch | HEAD | Role |
|---|---|---|
| `codi-v4.7.0-fazer-ai.6` | `735c745c8a` | **Active customization branch** — fazer-ai 4.7.6 + Click2Run features |
| `develop` | `c32536d8d2` | Older integration branch, last touched Nov 14 2025 (lags codi by 1 commit) |
| `main` | `8e245ea77d` | **Empty placeholder** (single "Initial commit" — not used) |
| `fazerai-main` | `be18159b00` | Mirror of fazerai/main snapshot |
| `fazerai-develop` | (synced) | Mirror of fazer-ai develop |
| `chatwoot-develop` | (synced) | Mirror of upstream chatwoot develop |

### 2.3 Tags relevant to upgrade path
We hold local tags `v4.5.1-fazer-ai.1` through `v4.7.0-fazer-ai.6` only. **Anything past 4.7.6 is remote-only** until fetched.

Recently fetched into local objects: `v4.9.0-fazer-ai.13` (via FETCH_HEAD).

### 2.4 Worktrees
```
/root/data/development/controledigital/chatwoot.git                    [codi-v4.7.0-fazer-ai.6]   ← main checkout (current)
/root/data/development/controledigital/chatwoot.git.worktrees/develop  [develop]                  ← stale upgrade attempt, 4065 dirty paths
```

---

## 3. Customization Layer (What Is "Ours")

### 3.1 Documentation files at the project root (all currently UNTRACKED)
These are the deliberate `CUSTOM_*` and `.codi/` separation strategy the user described:

| File | Size | Topic |
|---|---|---|
| `CUSTOM_FAZER-AI.md` | 19.5K | Catalog of fazer-ai's own customizations on top of upstream Chatwoot |
| `CUSTOM_CLICK2-RUN.md` | 46.1K | Click2Run product-level documentation |
| `CUSTOM_CLICK2RUN-API.md` | 79.4K | API contract & integration with Click2Run platform |
| `CUSTOM_AUTH.md` | 13.7K | `AUTH_DISABLE_DEFAULT` and `AUTH_SUPERADMIN_SAME_SESSION` env-var contract |
| `CUSTOM_CADDY.md` | 9.3K | Local HTTPS dev via Caddy reverse proxy |
| `CUSTOM_BRANDING.md` | 3.4K | Brand asset/env-var pipeline (already tracked) |
| `CUSTOM_WHATSAPP-QRCODE.md` | 8.1K | QR-code push-model architecture (Baileys + Whatsmeow webhook) |
| `CHATWOOT_READ-RECEIPTS.md` | 6.8K | Read-receipt notes |
| `.codi/CLICK2RUN_OPENID_INTEGRATION.md` | 29.1K | Full OpenID integration design |
| `.codi/CLICK2RUN_OPENID_SETUP.md` | 15.7K | Operational setup |
| `.codi/WHATSAPP_INTEGRATION.md` | 3.7K | WhatsApp provider notes |
| `.codi/WHATSMEOW_INTEGRATION.md` | 10.6K | Whatsmeow provider notes |

Recommendation: **commit these** to a docs commit on the working branch as the very first safe-state move (no code risk, clarifies what's authoritative).

### 3.2 Click2Run code commits ahead of `v4.7.0-fazer-ai.6`
37 commits, conceptually grouped:

**Authentication / OpenID**
- `5abc2b80a4` — feat: Click2Run OpenID integration with custom auth controls
- `d81ee08680` — refactor: standardize authentication branding to Click2Run OpenID Connect
- `d75953a6c8` — feat: optional Super Admin session reuse via ENV (`AUTH_SUPERADMIN_SAME_SESSION`)
- `8b5a062d03` / `ce777597c0` — Logto OAuth (parallel/secondary IdP path)
- `6b997b8882` — fix: Click2Run promo banner images and small fixes

**WhatsApp providers**
- `b98b08d19f` — feat: Click2Run WhatsApp provider integration
- `34f6fdca08` — feat: finalize Whatsmeow WhatsApp provider integration
- `2971cfb136` — feat: enhance WhatsApp provider configuration and feature management
- `30a5fb2189` — feat: Click2Run WhatsApp provider translations
- `3b92c24fdf` / `69de6e61cc` / `d9fd3cc642` — Whatsmeow UI / model / service
- `7ec6ecf750` — feat: feature flags & env config for providers
- `115da4afa0` — i18n updates (en/es/pt)

**Infrastructure / dev environment**
- `50bcc1af85` — fix: vite Docker (native gem support, faster startup)
- `156d742eea` — fix: improve Docker dev environment stability
- `7ede6d9e0b` — fix: Docker container init failures
- `c25dcafcb5` — fix: Rails 7.2 alias_method for User associations
- `a50aa214de` — fix: disable rubocop in pre-commit hook (Docker-only dev)
- `78595b1947` — fix: ENV vars override empty database config values
- `0c0484ffb8` — enhance: parse FRONTEND_URL for accurate URL generation
- `972d9034d0` — feat: enable web console in development
- `7c859b22f7` — fix: remove unsafe ActsAsTaggableOn call from migration
- `b9213821e7` — chore: schema/model annotations
- `1cb32886a8` — fix: dev environment configuration issues
- `1fae8cc999` — Configure Git LFS for large binaries

**UX / feature flags**
- `c46a1f754d` — fix: hide SLA Reports menu item when feature disabled
- `a2f4243a22` — fix: disable campaign creation buttons when no inbox exists
- `a8b0bd9f67` — chore: disable Z-API feature flag (compliance)

**Docs**
- `0449c36d9d` — docs: Fazer.AI customizations analysis
- `2b8982f1dc` — docs: Logto integration planning

### 3.3 Customization stat (HEAD vs `v4.7.0-fazer-ai.6`)
- **101 files changed**, 20,593 insertions, 625 deletions.
- 48 new files in HEAD that don't exist in the tag.
- 0 files removed in HEAD that exist in the tag.
- Notable inserts: `pnpm-lock.yaml` (38 lines, normal), `vendor/db/sentiment-analysis.onnx` (Git LFS pointer / 133 bytes).

### 3.4 Modified-but-uncommitted tracked files (4)
| File | Net change |
|---|---|
| `.env.example` | +9 lines — likely new env vars (auth/branding) |
| `app/javascript/v3/components/Click2RunOpenid/Button.vue` | ±31/11 lines — Button refinement |
| `app/javascript/v3/views/login/Index.vue` | +10 lines — `isDefaultAuthDisabled` integration in login UI |
| `app/views/layouts/vueapp.html.erb` | +2 lines — exposes `authDisableDefault` to `window.chatwootConfig` |

These match the design in `CUSTOM_AUTH.md` exactly — they are the implementation of `AUTH_DISABLE_DEFAULT`. They belong with that commit.

---

## 4. Working Tree Triage (the 906 untracked files)

`git ls-files --others --exclude-standard` returned **906 paths**. Cross-referenced against snapshots:

| Bucket | Count | Disposition |
|---|---|---|
| In `v4.9.0-fazer-ai.13` | 435 | Almost certainly the result of a partial newer-fazer-ai import. Source-of-truth is the tag — let the upgrade pull them. |
| In `chatwoot-develop` (subset of above) | 122 | Same — these will arrive via fazer-ai or upstream. |
| Not in `v4.9.13` and not in `chatwoot-develop` | **471** | **Triage required.** A spot-check found `app/builders/v2/reports/channel_summary_builder.rb` exists *only* on disk and in the `develop` worktree — it likely came from a Chatwoot intermediate version (between 4.7.6 and 4.9.13) or from upstream `develop` at a different point in time. |

**Hypothesized origin of the 471 "ghost" files**: the `chatwoot.git.worktrees/develop` worktree (created May 4 2026) staged a large in-flight upgrade (`A 885 / D 164 / M 3006 / R 10`) and someone evidently ran a copy/sync command that landed those files in this main checkout's working tree without an accompanying `git add`. Their May 4 birth-time matches the worktree directory's birth-time exactly.

**Risk**: silently committing them would polish-merge an unfinished upgrade attempt into the codi branch.

**Recommended handling — do NOT commit any of the 906 untracked files until each bucket is classified.**

The 4 modified files plus the 12 doc files in §3.1 should be the only things landed in the safe-state commit.

---

## 5. Upstream Drift — How Far We Are From Fazer-AI

**Local last fazer-ai tag**: `v4.7.0-fazer-ai.6` (`be18159b00`, Nov 6 2025).

**Available on remote** (chronological, newest last):
```
v4.7.0-fazer-ai.7
v4.8.0-fazer-ai.{1,2,3,4,5,6,7}
v4.9.0-fazer-ai.{1..13}
```

That is **21 tagged releases** to absorb. Fazer-AI's pattern (per `CUSTOM_FAZER-AI.md`) merges upstream Chatwoot every 2-4 weeks, so this represents:
- Upstream Chatwoot v4.8.x and v4.9.x merges
- Multiple new fazer-ai features (the user mentioned features evolved on their side)
- Likely changes to the WhatsApp provider architecture (Baileys/Z-API), branding, Coolify compose

**Evidence of architectural drift on fazer-ai**:
- Newer fazer-ai introduces `app/controllers/api/v1/accounts/articles/` (directory of split controllers) replacing the old single `articles_controller.rb`.
- Adds `app/controllers/tiktok/`, voice channel APIs, copilot UI, Year-in-Review, Captain agent endpoints, push diagnostics, platform banners.

**Concrete conflict zones to expect during the upgrade**:
1. **WhatsApp providers**: Click2Run's provider sits parallel to Baileys/Z-API/Whatsmeow. fazer-ai may have refactored those modules (commit `7a3544ba99 chore: remove zapi feature flag`, `16d7e68176 fix: fix zapi prop naming`) — verify our provider still slots in cleanly.
2. **Auth**: fazer-ai may add new auth-related callbacks; our `before_action :check_default_auth_disabled` shims must compose correctly.
3. **Login view**: `app/javascript/v3/views/login/Index.vue` is heavily customized for `isDefaultAuthDisabled` and the Click2Run button — high merge-conflict probability.
4. **Branding**: our `INSTALLATION_NAME` / banner-image overrides interact with `lib/tasks/branding.rake`; fazer-ai may have evolved that task.
5. **Docker / CI**: our vite Docker fixes (`50bcc1af85`) and dev-env stability fixes may overlap with fazer-ai's `docker-compose.coolify.yaml` updates (`be18159b00`).
6. **Database config / FRONTEND_URL parsing**: surgical infra patches (`78595b1947`, `0c0484ffb8`) — verify upstream hasn't independently fixed the same.

---

## 6. The New Variable: `whatsapp-api.git` (Propria.Cloud)

The user identified a sibling project at `/root/data/development/controledigital/whatsapp-api.git` (and worktrees `develop`, `merge-test`, `stable`, `staging`, `waba`). Worktree `develop` shows:

- **HEAD**: `76a57417 fix(events): IDResolver chain replaces broken fallback`
- **Branch**: `develop`
- **Self-described** in `docs/openapi.yaml`:
  > openapi: 3.1.0
  > info.title: WhatsApp API
  > "Production-ready REST API for WhatsApp functionality powered by whatsmeow.
  > A Propria.Cloud Solution by Controle Digital."
- **Footprint**: 117 API operations, 105 event types, 12 RabbitMQ queues, multi-instance, multi-tenant.
- **Capabilities**: messaging, groups, newsletters, polls, calls, app-state recovery, audit/recovery endpoints, paired-devices, embedded-signup-style flows, WABA (Meta WhatsApp Business API) support, plus their own whatsmeow fork ("whatsmeai").
- **Endpoint shape (relevant excerpts)**:
  ```
  /instances/create        /instances/connect       /instances/disconnect
  /instances/pair/qrcode   /instances/pair/phonecode
  /instances/unpair        /instances/recovery      /instances/audit/*
  /appstate/recovery       /appstate/sync
  /runtime/{instances,devices,stats}
  /docs/* (50+ doc pages)  /openapi.{json,yaml}
  ```

This **replaces** the conceptual seat occupied today by the local Click2Run/Whatsmeow provider service in this Chatwoot fork. Per the user's direction, after the fazer-ai upgrade is complete, the Click2Run WhatsApp provider in Chatwoot must be realigned to call **this** API contract (and follow its OpenAPI as the source of truth for endpoints, payloads, webhook events).

This is **out of scope for the upgrade itself** but constrains it: avoid investing time during the merge resolving fazer-ai's Baileys/Z-API evolutions in our Click2Run provider — instead aim to keep the Click2Run provider thin and isolatable, since it is on a re-implementation runway against `whatsapp-api`.

---

## 7. Risks & Constraints

| Risk | Severity | Mitigation |
|---|---|---|
| Working tree contains unidentified "ghost" files from a partial upgrade attempt | **High** | Triage the 471 non-fazer-ai/non-chatwoot files before any merge. Default to `git clean -fdn` dry-run, then `git stash --include-untracked` to capture for inspection rather than discard. |
| 21-tag jump = high cumulative conflict surface, especially in login UI / providers / Docker | **High** | Prefer **stepwise tag-by-tag merges** over a single jump. Each tag becomes a discrete commit on the working branch; bisectable if regressions appear. |
| Click2Run provider may break against an evolved Baileys/Whatsmeow surface | **Medium** | Keep the Click2Run provider isolated in its own files; avoid collateral edits during merge. The realignment to `whatsapp-api.git` is the longer-term destination anyway. |
| `develop` worktree contains 4065 staged paths — looks like an abandoned attempt | **Medium** | Do not merge from this worktree blindly. Treat as reference only; preserve via a backup branch (`git -C ../chatwoot.git.worktrees/develop stash push -u -m "wip-2026-05-04"`) before doing anything destructive. |
| Branch sprawl (`main` empty, `develop` stale, `codi-logto`, `fazerai-*`, `chatwoot-develop`) | Low | Document the role of each; consolidate after upgrade. |
| Eventual rebrand to **Propria Cloud** | Low (deferred) | Keep `INSTALLATION_NAME` / `BRAND_*` env-driven; user explicitly deferred rebrand until after upgrade. |
| `whatsapp-api.git` realignment is a separate, large effort | Tracked | Out of scope for this analysis pass — captured as Task #7. |

---

## 8. Recommended Strategy

### 8.1 Branching plan (post-analysis, pre-upgrade)
- **Working integration branch**: continue on `codi-v4.7.0-fazer-ai.6` for the safe-state commit, then create a **new branch** `codi-v4.9.0-fazer-ai.13` for the upgrade work. The branch name encodes the target fazer-ai tag, matching the existing convention.
- **Tag a restore point**: after the safe-state commit, tag it `codi-pre-upgrade-2026-05-07` and push to `origin`. This is the user-explicit "safe restore point as needed."
- **Push the current branch** to `origin/codi-v4.7.0-fazer-ai.6` if not already up-to-date, so the restore point exists off the local box.
- **Park** `develop`, `main`, the `chatwoot-develop` mirror, and the `fazerai-*` mirrors. They are not in the active path. Keep mirrors fetched but don't merge from them. The user explicitly said: *for now, focus on fazer-ai only and ignore upstream chatwoot.*
- **Park** the `chatwoot.git.worktrees/develop` worktree's in-flight changes (stash them with a descriptive message). Don't delete the worktree until we confirm no work needs salvaging.

### 8.2 Phased upgrade plan (proposed; awaiting user sign-off)

**Phase 0 — Safe state (no code risk)**
- 0.1 Triage the 906 untracked files into three buckets: ours (commit), fazer-ai noise (ignore — will arrive via tag merge), and unidentified (stash for review).
- 0.2 Commit the 12 documentation files (§3.1) under one `docs(custom): …` commit.
- 0.3 Commit the 4 modified tracked files implementing `AUTH_DISABLE_DEFAULT` under `feat(auth): wire AUTH_DISABLE_DEFAULT through login & layout` (matching `CUSTOM_AUTH.md`).
- 0.4 Stash everything else with `git stash push -u -m "pre-upgrade-untracked-2026-05-07"`.
- 0.5 Tag `codi-pre-upgrade-2026-05-07`, push branch + tag to `origin`.

**Phase 1 — Move to a target branch**
- 1.1 `git checkout -b codi-v4.9.0-fazer-ai.13`
- 1.2 Confirm green local boot still works (Docker/Caddy bring-up + Rails console + login page render). Establishes the "before" baseline.

**Phase 2 — Stepwise fazer-ai merges (preferred)**
For each tag in order:
```
v4.7.0-fazer-ai.7
v4.8.0-fazer-ai.1 ... v4.8.0-fazer-ai.7
v4.9.0-fazer-ai.1 ... v4.9.0-fazer-ai.13
```
- 2.1 `git fetch fazerai tag <tag>`
- 2.2 `git merge --no-ff <tag>` with conflict resolution per the rules in §5.
- 2.3 Smoke-test the boot path after each merge (or at least every 4-5 tags).
- 2.4 Keep merge commits — they are valuable for `git log --first-parent` archaeology later.

If the cumulative conflict load proves prohibitive, the fallback is to merge the single latest tag (`v4.9.0-fazer-ai.13`) and resolve in one pass — but that loses bisectability.

**Phase 3 — Customization re-validation**
- 3.1 Verify each Click2Run feature still functions (OpenID flow, `AUTH_DISABLE_DEFAULT`, branding, Caddy dev HTTPS, vite Docker stability, Click2Run/Whatsmeow inboxes, banner images, SLA/campaign UI gates).
- 3.2 Re-evaluate which custom commits are now redundant (upstream may have fixed the same issue independently — e.g., `78595b1947` ENV-override-on-empty-DB, `0c0484ffb8` FRONTEND_URL parsing, `c25dcafcb5` Rails 7.2 alias_method).

**Phase 4 — Tag, push, document**
- 4.1 Tag `codi-v4.9.0-fazer-ai.13.1` (first codi release on the new fazer-ai base).
- 4.2 Update `CUSTOM_FAZER-AI.md` with the new "merge upstream history" entries.
- 4.3 Write a conclusion file at `.llm/conclusions/<timestamp>-fazer-ai-v4.9.13-upgrade-complete.md` per project directives.

**Phase 5 — Deferred (separate engagement)**
- 5.1 Realign Click2Run WhatsApp provider to `whatsapp-api.git`'s OpenAPI 3.1 contract. Use `docs/openapi.yaml` as source of truth.
- 5.2 Eventual rebrand from "Click2Run" → "Propria Cloud" through the existing brand env-var pipeline (no code rename required if the env-driven branding holds; namespaces like `Click2RunOpenid` are a separate choice).

### 8.3 What we are explicitly NOT doing in this engagement
- Not pulling from `upstream/chatwoot` directly. The user said: ignore chatwoot upstream for now and focus on fazer-ai-only compliance.
- Not rebranding Click2Run → Propria Cloud in this pass.
- Not rewriting the WhatsApp provider against `whatsapp-api.git` in this pass.
- Not removing the `Logto` parallel auth path unless the user asks (it's currently dormant — `dbb35fcefd Merge branch 'codi-v4.7.0-fazer-ai.4' into codi-logto`).

---

## 9. Open Questions for the User (before Phase 0 starts)

1. **Authoritative branch**: should the post-upgrade branch be `codi-v4.9.0-fazer-ai.13` (mirrors the fazer-ai tag exactly) or simply `codi-develop` going forward? The current convention encodes the version into the branch name, which means a new branch every fazer-ai bump. That's verbose but very explicit. A rolling `codi-develop` is lighter.
2. **Stepwise vs single merge**: 21 incremental tag merges (slower, bisectable) or a single jump to `v4.9.0-fazer-ai.13` (faster, opaque)?
3. **Logto path**: keep the dormant Logto auth code, or remove it now that Click2Run OpenID is the primary IdP?
4. **The 471 "ghost" files**: stash-and-discard, or do you want each one classified individually before discard?
5. **Worktree `develop`**: is there work in there you wanted to salvage, or is it purely an abandoned attempt that can be parked/pruned after a stash backup?

---

## 10. Inventory References

- This analysis: `.llm/analysis/20260507214114-analysis-project-state-and-fazer-ai-upgrade-strategy.md`
- Companion plan (to be written after Q&A): `.llm/project/002-planning/<ts>-fazer-ai-upgrade-plan.md`
- Companion conclusion (after work is done): `.llm/conclusions/<ts>-fazer-ai-v4.9.13-upgrade-complete.md`
