---
Created: 2025-11-05T00:00:00Z
Operation: Docker Compose Volume Optimization Analysis
Context: Investigating slow container startup due to missing cache volumes
Related Files:
  - docker-compose.yaml
  - docker/entrypoints/vite.sh
  - docker/entrypoints/rails.sh
  - docker/dockerfiles/vite.Dockerfile
---

# Docker Compose Volume Optimization Analysis

## Current State

The docker-compose.yaml has these volumes:
- `bundle:/usr/local/bundle` → Ruby gems
- `node_modules:/app/node_modules` → NPM packages
- `packs:/app/public/packs` → Compiled assets
- `cache:/app/tmp/cache` → General cache (DELETED on startup!)

## Problems Identified

### 1. PNPM Store Not Cached (Critical)
**Issue**: `vite.sh:23` runs `pnpm install --force` without persistent store
**Impact**: Downloads ~500MB+ packages on every container restart
**Solution**: Add volume for `/root/.local/share/pnpm/store`

### 2. Cache Directory Deleted on Startup
**Issue**: `vite.sh:5` and `rails.sh:7` run `rm -rf /app/tmp/cache/*`
**Impact**: Bootsnap compilation cache, Vite cache, all deleted
**Solution**: Only delete PIDs, preserve cache subdirectories

### 3. Git Hardlink Errors in Bundle
**Issue**: `devise-secure_password` git gem fails with hardlink errors
**Current Workaround**: Delete and re-clone on failure
**Impact**: Slow bundle install on first failure
**Root Cause**: Docker volume doesn't preserve git object cache properly
**Solution**: Persist `/gems/ruby/3.4.0/cache/bundler/git`

### 4. Yarn/NPM Cache Not Persisted
**Issue**: If fallback to npm/yarn occurs, no cache exists
**Impact**: Slower fallback package installation

### 5. Turbo Cache Not Persisted
**Issue**: Vite/Turbo build cache not preserved
**Impact**: Slower frontend builds on restart

## Recommended Volumes to Add

```yaml
volumes:
  postgres:
  redis:
  packs:
  node_modules:
  cache:              # Keep but stop deleting contents
  bundle:
  pnpm_store:         # NEW - PNPM global store
  git_bundler_cache:  # NEW - Git gem cache
  vite_cache:         # NEW - Vite build cache
  yarn_cache:         # NEW - Yarn cache (fallback)
```

## Entrypoint Script Changes

### vite.sh - Before
```bash
rm -rf /app/tmp/cache/*
pnpm store prune
pnpm install --force
```

### vite.sh - After
```bash
# Only remove PIDs, not cache
rm -rf /app/tmp/pids/server.pid
# Don't prune store - let it accumulate
# pnpm store prune  # REMOVED
# Use cached store instead of --force
pnpm install
```

## Estimated Performance Impact

| Operation | Current | Optimized | Improvement |
|-----------|---------|-----------|-------------|
| Vite container startup | ~3-5 min | ~30 sec | 6-10x faster |
| Bundle install (cached) | ~1 min | ~10 sec | 6x faster |
| First boot (cold) | ~5-7 min | ~2-3 min | 2-3x faster |
| Subsequent boots | ~3-5 min | ~30-60 sec | 5x faster |

## Additional Considerations

1. **Volume Size**: PNPM store can grow to 2-3GB over time
2. **Cleanup**: Periodic `docker volume prune` needed
3. **Sharing**: Bundle volume shared across rails/sidekiq/vite already
4. **Build vs Runtime**: These caches only help runtime, not image builds
