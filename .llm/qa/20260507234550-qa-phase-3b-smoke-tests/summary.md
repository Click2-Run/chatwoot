---
Created: 2026-05-07T23:45:50Z
Feature: Phase 3b — Best-effort smoke tests after fazer-ai v4.9.13 upgrade
Total Cycles: 2 (one diagnostic + one passing)
Final Status: PASS (JS / vitest); Ruby/integration deferred to user (no Docker on host)
---

## Result

PASS for everything that can be validated outside Docker:

- ESLint: clean on Click2Run-touched files
- Conflict markers: none anywhere in tree
- Routes: all upstream 4.9.0 features (TikTok, Voice, Year-in-Review) registered; Click2Run + Whatsmeow webhook routing intact
- WhatsApp providers: `app/jobs/webhooks/whatsapp_events_job.rb` correctly dispatches `baileys`, `zapi`, `whatsmeow`, `click2run` provider strings
- WhatsApp model: `app/models/channel/whatsapp.rb` PROVIDERS = `%w[default whatsapp_cloud baileys zapi whatsmeow click2run]`
- vitest: **335/335 test files passed, 2812 tests passed, 18 skipped, 0 failed** (after pinning vite-plugin-ruby to 5.1.1 and regenerating pnpm-lock to include pinia)

## Cycles

### Cycle 1 — Diagnostic (red → fixed)
**Trigger:** initial `pnpm test` after the merges.

**Failures observed:**
- 7/335 test files failed loading with `Failed to resolve import "pinia"` — pinia is required by upstream Voice Channel feature added in v4.9.0-fazer-ai.8 but not installed.
- 328/335 test files passed; 2638 tests passed.

**Root cause:** during the v4.8.0-fazer-ai.1 conflict resolution, `pnpm-lock.yaml` was taken from theirs (`v4.8.0-fazer-ai.1`) — pre-pinia. Subsequent merges added `pinia` to `package.json` but the lockfile stayed stale.

**Fix:**
1. `pnpm install --no-frozen-lockfile` to regenerate the lockfile against the merged `package.json`.
2. The regen also bumped `vite-plugin-ruby` 5.1.1 → 5.2.2; 5.2.2 is ESM-only and breaks the CommonJS `vite.config.ts`. Pinned `vite-plugin-ruby` to exact `5.1.1` in `package.json` and reran `pnpm install --no-frozen-lockfile`. Committed as `ca2bba88a0 fix(deps): pin vite-plugin-ruby to 5.1.1 (avoid ESM-only 5.2.x)`.

### Cycle 2 — Verification (green)
**Command:** `pnpm test`
**Result:**

```
Test Files  335 passed (335)
     Tests  2812 passed | 18 skipped (2830)
  Start at  23:35:41
  Duration  602.23s (transform 29.84s, setup 1231.90s, collect 58.42s, tests 7.07s, environment 290.12s, prepare 53.62s)
```

Exit code 0.

## What was NOT validated (requires Docker / live environment)

These remain user-side smoke tests:

- [ ] `bundle install` regenerates `Gemfile.lock` against merged Gemfile (no Ruby on host)
- [ ] `bundle exec rails db:migrate` succeeds and produces the expected `db/schema.rb`
- [ ] `bundle exec rspec` Ruby test suite
- [ ] `ruby -c` syntax check on the 32 Ruby files changed in the merge surface
- [ ] Rails boot, Sidekiq boot
- [ ] Login page renders both with and without `AUTH_DISABLE_DEFAULT`
- [ ] Click2Run/Logto OIDC sign-in round-trip (gated on Phase 5a-followup credential apply)
- [ ] SuperAdmin `AUTH_SUPERADMIN_SAME_SESSION` toggle
- [ ] Click2Run / Whatsmeow / Baileys / Z-API inbox creation flows
- [ ] Branding env-var override
- [ ] Caddy reverse proxy + HTTPS local dev
- [ ] Vite dev rebuild with native gem support
- [ ] Voice Channel + TikTok + Year-in-Review (upstream 4.9.0 features) functional smoke
- [ ] Cross-cutting feature flag interactions (`channel_*`, `companies`, `channel_tiktok`)

The user can run these in their Docker / Coolify environment (`docker compose up -d` then the verification recipe in the conclusion doc).

## Final Verification Checklist

- [x] No conflict markers anywhere (`grep -rn '<<<<<<< |======= $|>>>>>>> ' app/ config/ db/ docker/ enterprise/ spec/` returns nothing)
- [x] ESLint clean on the 5 Click2Run-touched files (login Index.vue, OpenID Button.vue, ChannelItem.vue, Sidebar.vue, featureFlags.js)
- [x] Routes register: `companies`, `tiktok`, `year_in_review`, `voice`, `webhooks/tiktok` — verified via grep
- [x] WhatsApp event dispatcher routes `baileys`, `zapi`, `whatsmeow`, `click2run`
- [x] vitest 335/335 files green
- [x] vite.config.ts loads cleanly (vite-plugin-ruby ESM regression fixed)
- [x] All Click2Run / Whatsmeow files present on disk
- [x] No customisation env vars lost (Phase 3a audit)
- [x] All 5 codi refs live on `origin` (2 branches + 2 tags + the new branch)
