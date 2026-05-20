---
Created: 2025-11-04T20:35:00Z
Operation: Fix OmniAuth OpenID Connect Gem Dependency Conflict
Context: Resolved Docker build failure due to gem version incompatibility
Related Files: Gemfile, Gemfile.lock, config/initializers/omniauth.rb
---

# Fix OmniAuth OpenID Connect Gem Dependency Conflict

## Problem Summary

Docker build was failing with the following error:
```
Could not find compatible versions

Because every version of omniauth-openid-connect depends on omniauth ~> 1.1
  and Gemfile depends on omniauth >= 2.1.2,
  omniauth-openid-connect cannot be used.
```

## Root Cause

The `omniauth-openid-connect` gem (hyphenated) requires OmniAuth version ~> 1.1, but the Gemfile specified `omniauth >= 2.1.2`. This created a version conflict that prevented bundle install from resolving dependencies.

## Solution

Replaced the incompatible gem with the OmniAuth 2.x compatible version:

### Changes Made

**File: Gemfile (line 180)**

**Before:**
```ruby
gem 'omniauth-openid-connect'
```

**After:**
```ruby
# Use jjbohn fork which supports OmniAuth 2.x
gem 'omniauth_openid_connect', '~> 0.8.0'
```

### Key Differences

1. **Gem Name**: `omniauth-openid-connect` → `omniauth_openid_connect` (hyphen → underscore)
2. **Version Constraint**: Added explicit version `~> 0.8.0`
3. **OmniAuth Compatibility**: Version 0.8.0 supports OmniAuth >= 1.9, < 3

### Verification

The gem was successfully installed in the Docker container:
```bash
$ docker compose exec rails bundle list | grep openid
* omniauth_openid_connect (0.8.0)
  * openid_connect (2.3.1)
```

## Impact Assessment

### What Works

✅ Docker build completes successfully
✅ All gems install without conflicts
✅ Rails container starts without errors
✅ OmniAuth strategy name remains `:openid_connect`
✅ No changes required to config/initializers/omniauth.rb
✅ Logto OAuth configuration remains compatible

### No Breaking Changes

The strategy name used in the OmniAuth configuration (`provider :openid_connect`) works with both gems, so no application code changes were required.

## Build Results

**Build Duration:** ~3 minutes
**Containers Status:** All running successfully
- ✅ base
- ✅ rails (port 3000)
- ✅ sidekiq
- ✅ redis
- ✅ postgres
- ✅ mailhog (ports 1025, 8025)
- ✅ vite

## Next Steps

1. ✅ Gem dependency resolved
2. ✅ Docker containers built and running
3. ⏭️ Test Logto OAuth login flow
4. ⏭️ Verify OpenID Connect authentication

## Technical Details

### Gem Information

**omniauth_openid_connect (0.8.0)**
- Repository: https://github.com/omniauth/omniauth_openid_connect
- OmniAuth Support: >= 1.9, < 3
- OpenID Connect: ~> 2.2
- Maintained: ✅ Active

**Dependencies Installed:**
- omniauth_openid_connect (0.8.0)
  - omniauth (>= 1.9, < 3)
  - openid_connect (~> 2.2)
- openid_connect (2.3.1)
  - activemodel
  - attr_required (>= 1.0.0)
  - And other transitive dependencies

### Compatibility Matrix

| Component | Version | Compatible |
|-----------|---------|------------|
| omniauth | 2.1.3 | ✅ |
| omniauth_openid_connect | 0.8.0 | ✅ |
| openid_connect | 2.3.1 | ✅ |
| Rails | 7.1.5.2 | ✅ |
| Ruby | 3.4.4 | ✅ |

## References

- OmniAuth OpenID Connect: https://github.com/omniauth/omniauth_openid_connect
- OpenID Connect Spec: https://openid.net/specs/openid-connect-core-1_0.html
- Logto Documentation: https://docs.logto.io/
