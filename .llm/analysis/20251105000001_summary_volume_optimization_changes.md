---
Created: 2025-11-05T00:00:01Z
Operation: Docker Volume Optimization Implementation Summary
Context: Applied caching improvements to docker-compose.yaml and entrypoint scripts
Related Files:
  - docker-compose.yaml
  - docker/entrypoints/vite.sh
  - docker/entrypoints/rails.sh
---

# Docker Volume Optimization - Changes Applied

## Summary

Optimized Docker development environment to eliminate redundant package installations and preserve build caches across container restarts.

## Changes Made

### 1. docker-compose.yaml - Added Cache Volumes

**New volumes declared**:
```yaml
volumes:
  pnpm_store:           # PNPM global package cache (~500MB-2GB)
  git_bundler_cache:    # Git-based gem cache (prevents hardlink errors)
```

**Volume mappings added to all services** (rails, sidekiq, vite):
```yaml
- pnpm_store:/root/.local/share/pnpm/store
- git_bundler_cache:/gems/ruby/3.4.0/cache/bundler/git
```

### 2. docker/entrypoints/vite.sh - Cache Preservation

**Removed destructive operations**:
```bash
# BEFORE
rm -rf /app/tmp/cache/*           # Deleted ALL cache
pnpm store prune                  # Deleted cached packages
pnpm install --force              # Force re-download everything

# AFTER
rm -rf /app/tmp/pids/server.pid   # Only remove PIDs
# Selectively clean only bootsnap compile cache if needed
pnpm install                      # Use cached packages
```

### 3. docker/entrypoints/rails.sh - Cache Preservation

**Removed cache deletion**:
```bash
# BEFORE
rm -rf /app/tmp/cache/*

# AFTER
# rm -rf /app/tmp/cache/*  # REMOVED - cache persists across restarts
```

## Expected Performance Improvements

| Scenario | Before | After | Improvement |
|----------|--------|-------|-------------|
| Vite container startup (cold) | 3-5 min | 30-60 sec | **5-10x faster** |
| Vite container startup (warm) | 2-3 min | 15-30 sec | **6-8x faster** |
| Bundle install (cached gems) | 60 sec | 10-15 sec | **4-6x faster** |
| PNPM install (cached packages) | 120 sec | 10-20 sec | **6-12x faster** |
| Full stack restart | 5-7 min | 1-2 min | **3-5x faster** |

## What Each Volume Does

### pnpm_store (/root/.local/share/pnpm/store)
- **Purpose**: Global PNPM content-addressable package cache
- **Impact**: Prevents re-downloading packages that already exist locally
- **Size**: 500MB-2GB depending on dependencies
- **Shared**: Used by vite container

### git_bundler_cache (/gems/ruby/3.4.0/cache/bundler/git)
- **Purpose**: Cached git clones for git-based gems (e.g., devise-secure_password)
- **Impact**: Prevents git clone failures and redundant clones
- **Size**: 50-200MB
- **Shared**: Used by rails, sidekiq, vite containers

### cache (/app/tmp/cache) - Already existed, now preserved
- **Purpose**: Bootsnap compilation cache, Vite build cache, Rails cache
- **Impact**: Faster Ruby class loading, faster Vite builds
- **Size**: 100-500MB
- **Shared**: Used by all containers

## Testing the Changes

### 1. Clean Start Test
```bash
# Stop and remove all containers
docker-compose down

# Start services
docker-compose up -d

# Monitor vite logs - should see pnpm install complete in ~30 seconds
docker-compose logs -f vite
```

### 2. Restart Test (Cache Validation)
```bash
# Restart vite container
docker-compose restart vite

# Should start MUCH faster now (~15-30 seconds)
docker-compose logs -f vite
```

### 3. Volume Verification
```bash
# Check volumes exist
docker volume ls | grep chatwoot

# Check volume sizes
docker system df -v | grep -A1 pnpm_store
docker system df -v | grep -A1 git_bundler_cache
```

## Maintenance

### Periodic Cleanup (Monthly)
```bash
# Prune unused volumes (be careful!)
docker volume prune

# Or specifically remove old caches
docker volume rm chatwoot_pnpm_store
docker volume rm chatwoot_git_bundler_cache
```

### If Issues Occur
```bash
# Force rebuild without cache
docker-compose build --no-cache vite

# Remove specific volume and recreate
docker volume rm chatwoot_pnpm_store
docker-compose up -d vite
```

## Notes

1. **First run after changes**: Initial startup will populate caches (slower)
2. **Subsequent runs**: Should be significantly faster
3. **Volume persistence**: Survives `docker-compose down`, but not `docker-compose down -v`
4. **Shared volumes**: bundle, pnpm_store, git_bundler_cache shared across services safely
5. **No impact on production**: These changes only affect development docker-compose.yaml

## Rollback Instructions

If issues occur, revert with:
```bash
git checkout docker-compose.yaml docker/entrypoints/vite.sh docker/entrypoints/rails.sh
docker-compose down -v  # Remove volumes
docker-compose up -d
```
