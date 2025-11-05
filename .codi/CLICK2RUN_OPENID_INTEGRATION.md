# Click2Run OpenID Connect Integration Plan for Chatwoot

**Branch:** `codi-click2run` (legacy name, now handles Click2Run OpenID)
**Date:** 2025-11-04
**Last Updated:** 2025-11-05
**Status:** Completed (Simplified OmniAuth Implementation)

---

## Executive Summary

This document outlines the integration of Click2Run Auth (OpenID Connect) as an identity provider for Chatwoot while maintaining compatibility with upstream updates and preserving existing authorization logic.

**Note:** Click2Run Auth is for the Click2Run ecosystem.

### Approach: OmniAuth OpenID Connect Provider

This hybrid approach provides:
- ✅ Centralized identity management across all applications
- ✅ Minimal divergence from upstream Chatwoot (upstream merge friendly)
- ✅ No migration complexity (new deployment)
- ✅ Maintainable custom code (~400 lines total)

---

## Architecture Overview

```
┌──────────────────────────────────────────┐
│  CLICK2RUN AUTH (Identity Provider)      │
│  - OpenID Connect / OAuth2               │
│  -              │
│  - User database, MFA, SSO, etc.         │
│  - Organizations = Chatwoot Accounts     │
└────────────┬─────────────────────────────┘
             │ OpenID Connect flow
             │ ID tokens + user info
             ▼
┌──────────────────────────────────────────┐
│  CHATWOOT (Consumer Application)         │
│                                           │
│  ┌────────────────────────────────────┐  │
│  │ OmniAuth Middleware                 │  │
│  │ config/initializers/omniauth.rb     │  │
│  │                                     │  │
│  │ - OpenID Connect provider           │  │
│  │ - Provider name: :click2run         │  │
│  │ - Handles OAuth flow automatically  │  │
│  └────────────┬───────────────────────┘  │
│               │                           │
│  ┌────────────▼───────────────────────┐  │
│  │ DeviseOverrides::                   │  │
│  │   OmniauthCallbacksController       │  │
│  │                                     │  │
│  │ - Handles /omniauth/click2run/      │  │
│  │   callback                          │  │
│  │ - Creates/updates User record       │  │
│  │ - Signs in user via Devise          │  │
│  └────────────┬───────────────────────┘  │
│               │                           │
│  ┌────────────▼───────────────────────┐  │
│  │ User Model                          │  │
│  │ - email, name, provider             │  │
│  │ - Uses existing Devise setup        │  │
│  │ - Standard Chatwoot user model      │  │
│  └────────────┬───────────────────────┘  │
│               │                           │
│  ┌────────────▼───────────────────────┐  │
│  │ AccountUser, Policies, etc.         │  │
│  │ (UNCHANGED - existing Chatwoot)     │  │
│  └─────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

---

## Key Design Decisions

### 1. Shadow User Records
- Chatwoot maintains lightweight User records synchronized from Click2Run Auth
- Users authenticate via Click2Run Auth, but Chatwoot needs local records for:
  - Foreign key relationships (AccountUser, Messages, etc.)
  - Session management
  - Authorization context (Current.user)

### 2. Organization Mapping
```
Click2Run Auth Organization → Chatwoot Account
Click2Run Auth Org Owner    → Chatwoot Administrator
Click2Run Auth Org Member   → Chatwoot Agent
```

### 3. Preserved Chatwoot Features
All existing authorization, multi-tenancy, and business logic remains unchanged:
- ✅ User model (shadow records only)
- ✅ AccountUser model (roles per account)
- ✅ Pundit policies (21 files, 617 lines)
- ✅ Current context system
- ✅ Multi-account membership
- ✅ Inbox members, team members
- ✅ Enterprise custom roles
- ✅ Audit logging
- ✅ Access tokens for bots/integrations
- ✅ SuperAdmin system

---

## Implementation Timeline

### Phase 1: Click2Run Auth Setup (Week 1)

**Objective:** Configure Click2Run Auth tenant and application

**Tasks:**
1. Create Click2Run Auth Application (Traditional Web App)
2. Configure redirect URIs:
   - Development: `http://localhost:3000/auth/click2run/callback`
   - Production: `https://your-domain.com/auth/click2run/callback`
3. Set up scopes: `openid`, `profile`, `email`, `organizations`
4. Create initial organizations (mapped to Chatwoot Accounts)
5. Define organization roles:
   - `owner` → Maps to Chatwoot Administrator
   - `admin` → Maps to Chatwoot Administrator
   - `member` → Maps to Chatwoot Agent
6. Document Click2Run Auth application credentials

**Deliverables:**
- Click2Run Auth tenant configured
- Environment variables documented
- Test user accounts created in Click2Run Auth

**Files Modified:**
- `.env` (add Click2Run Auth configuration)

---

### Phase 2: Backend Integration (Week 2-3)

**Objective:** Implement Click2Run Auth authentication strategy and user provisioning

#### Task 2.1: Custom Devise Strategy

**File:** `lib/devise/strategies/click2run_authenticatable.rb` (~80 lines)

**Purpose:** Validates Click2Run Auth JWT tokens and creates/finds shadow User records

**Key Features:**
- JWT signature validation using Click2Run Auth's JWKS endpoint
- Automatic user provisioning on first login
- Token caching for performance
- Error handling for invalid/expired tokens

**Implementation Notes:**
- Strategy checks for Bearer token in Authorization header
- Decodes JWT and validates against Click2Run Auth's public keys
- Creates User record with `provider: 'click2run'` and `uid: claims['sub']`
- No password stored (authentication happens in Click2Run Auth)

**Dependencies:**
- `jwt` gem (already in Gemfile)

#### Task 2.2: Click2Run Auth Organization Sync Service

**File:** `app/services/click2run/organization_sync_service.rb` (~100 lines)

**Purpose:** Synchronizes Click2Run Auth organizations and user roles to Chatwoot

**Key Features:**
- Fetches user's organizations from Click2Run Auth API
- Creates/updates Account records mapped to Click2Run Auth orgs
- Creates/updates AccountUser records with correct roles
- Role mapping: owner/admin → administrator, member → agent

**API Requirements:**
- Click2Run Auth Management API access (M2M token)
- Endpoint: `/api/users/{userId}/organizations`

**Implementation Notes:**
- Requires machine-to-machine (M2M) application in Click2Run Auth
- Cache M2M tokens (1 hour TTL)
- Handle API errors gracefully
- Idempotent sync operations

#### Task 2.3: Callback Controller

**File:** `app/controllers/auth/click2run_controller.rb` (~60 lines)

**Purpose:** Handles OAuth2 authorization code callback from Click2Run Auth

**Flow:**
1. Receive authorization code from Click2Run Auth
2. Exchange code for tokens (access, ID, refresh)
3. Validate ID token
4. Create/update User record
5. Sync organizations and roles
6. Sign in user (create Devise session)
7. Redirect to dashboard

**Security:**
- CSRF protection via state parameter
- Token validation before user creation
- Session fixation prevention

#### Task 2.4: Database Migration

**File:** `db/migrate/YYYYMMDDHHMMSS_add_click2run_fields.rb` (~10 lines)

**Changes:**
```ruby
# accounts table
add_column :accounts, :click2run_org_id, :string
add_index :accounts, :click2run_org_id, unique: true

# users table
add_column :users, :click2run_synced_at, :datetime
```

**Purpose:**
- `click2run_org_id`: Links Chatwoot Account to Click2Run Auth Organization
- `click2run_synced_at`: Tracks last sync timestamp for debugging

#### Task 2.5: Configuration Updates

**File:** `config/initializers/devise.rb` (+5 lines)

Add Click2Run Auth strategy to Warden:
```ruby
config.warden do |manager|
  manager.strategies.add(:click2run_authenticatable, Devise::Strategies::Click2Run AuthAuthenticatable)
  manager.default_strategies(scope: :user).unshift :click2run_authenticatable
end
```

**File:** `config/routes.rb` (+3 lines)

Add callback route:
```ruby
namespace :auth do
  get 'click2run/callback', to: 'click2run#callback'
end
```

**Deliverables:**
- Custom Devise strategy implemented and tested
- Organization sync service functional
- Callback controller handling OAuth2 flow
- Database migration applied
- Configuration files updated

**Testing Checklist:**
- [ ] JWT validation works with Click2Run Auth tokens
- [ ] User record created on first login
- [ ] Organizations synced correctly
- [ ] Roles mapped properly (owner → admin, member → agent)
- [ ] Callback flow completes without errors
- [ ] Session created successfully

---

### Phase 3: Frontend Integration (Week 4)

**Objective:** Replace Chatwoot login UI with Click2Run Auth authentication

#### Task 3.1: Update Login Page

**File:** `app/javascript/v3/views/login/Index.vue` (~50 lines, complete replacement)

**Changes:**
- Remove password/email form
- Add "Sign in with Click2Run Auth" button
- Implement OIDC authorization redirect
- Add state parameter for CSRF protection
- Store state in sessionStorage for validation

**Flow:**
1. User clicks "Sign in with Click2Run Auth"
2. Generate random state
3. Store state in sessionStorage
4. Redirect to Click2Run Auth authorization endpoint
5. Click2Run Auth handles authentication (MFA, SSO, etc.)
6. Click2Run Auth redirects back to callback URL with code

**OIDC Parameters:**
- `client_id`: Click2Run Auth application ID
- `redirect_uri`: Callback URL
- `response_type`: code
- `scope`: openid profile email organizations
- `state`: Random CSRF token
- `prompt`: login (force fresh authentication)

#### Task 3.2: Environment Variables for Frontend

**File:** `.env` or Vite config

Add frontend-accessible variables:
```bash
VITE_CLICK2RUN_ENDPOINT=https://your-tenant.click2run.app
VITE_CLICK2RUN_APP_ID=your_app_id
```

**Note:** Never expose `CLICK2RUN_APP_SECRET` to frontend

#### Task 3.3: Remove Unused Login Routes (Optional)

**Files to potentially remove/update:**
- Password reset flow (now handled by Click2Run Auth)
- Email confirmation flow (Click2Run Auth handles verification)
- Social OAuth buttons (Google, SAML - migrate to Click2Run Auth connectors)

**Recommendation:** Keep as fallback during migration, remove after stable

**Deliverables:**
- Login page redirects to Click2Run Auth
- State parameter validation working
- Successful authentication redirects to dashboard
- Error handling for failed authentication

**Testing Checklist:**
- [ ] Login button redirects to Click2Run Auth
- [ ] State parameter generated and validated
- [ ] Successful login redirects to dashboard
- [ ] Failed login shows error message
- [ ] MFA flow works (if enabled in Click2Run Auth)
- [ ] SSO flow works (if configured in Click2Run Auth)

---

### Phase 4: Organization Management (Week 5)

**Objective:** Implement bi-directional sync between Click2Run Auth and Chatwoot

#### Task 4.1: Webhook Handler for Click2Run Auth Events

**File:** `app/controllers/webhooks/click2run_controller.rb` (~80 lines)

**Purpose:** Handle events from Click2Run Auth (user created/updated, org membership changed)

**Supported Events:**
- `User.Created`: Provision new user in Chatwoot
- `User.Updated`: Sync user profile changes
- `User.Deleted`: Soft-delete or disable user
- `OrganizationMembership.Created`: Add user to Account
- `OrganizationMembership.Updated`: Update role
- `OrganizationMembership.Deleted`: Remove user from Account

**Security:**
- Verify webhook signature (Click2Run Auth signing secret)
- Validate payload structure
- Idempotent processing (handle duplicate events)

**Implementation:**
```ruby
class Webhooks::Click2Run AuthController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_click2run_signature

  def handle_event
    case params[:event]
    when 'User.Created'
      Click2Run Auth::ProvisioningService.new.create_user(params[:data])
    when 'User.Updated'
      Click2Run Auth::ProvisioningService.new.sync_user(params[:data])
    when 'OrganizationMembership.Updated'
      Click2Run Auth::OrganizationSyncService.new.sync_membership(params[:data])
    end

    head :ok
  end

  private

  def verify_click2run_signature
    # Verify webhook signature using signing secret
    # Implementation depends on Click2Run Auth's webhook signature method
  end
end
```

**Routes:**
```ruby
post 'webhooks/click2run', to: 'webhooks/click2run#handle_event'
```

#### Task 4.2: Periodic Sync Job (Fallback)

**File:** `app/jobs/click2run/sync_organizations_job.rb` (~40 lines)

**Purpose:** Periodic sync as fallback for webhook failures

**Schedule:** Run every 6 hours

**Implementation:**
```ruby
class Click2Run Auth::SyncOrganizationsJob < ApplicationJob
  queue_as :default

  def perform
    User.where(provider: 'click2run').find_each do |user|
      Click2Run Auth::OrganizationSyncService.new(user).sync_organizations
    rescue StandardError => e
      Rails.logger.error("Failed to sync orgs for user #{user.id}: #{e.message}")
    end
  end
end
```

**Scheduler Configuration:**
```ruby
# config/initializers/scheduler.rb (if using Sidekiq Scheduler)
Sidekiq::Cron::Job.create(
  name: 'Click2Run Auth Organization Sync',
  cron: '0 */6 * * *', # Every 6 hours
  class: 'Click2Run Auth::SyncOrganizationsJob'
)
```

#### Task 4.3: Account Creation in Click2Run Auth (Optional)

**File:** `app/services/click2run/account_provisioning_service.rb` (~60 lines)

**Purpose:** Create Click2Run Auth organizations when Chatwoot Accounts are created

**Use Case:** If admins create accounts in Chatwoot UI

**Implementation:**
```ruby
class Click2Run Auth::AccountProvisioningService
  def create_organization(account)
    # Call Click2Run Auth Management API to create org
    response = http_post("/api/organizations", {
      name: account.name,
      description: "Chatwoot Account: #{account.name}"
    })

    # Store Click2Run Auth org ID
    account.update!(click2run_org_id: response['id'])
  end
end
```

**Hook:** Add `after_create` callback to Account model

**Deliverables:**
- Webhook endpoint handling Click2Run Auth events
- Periodic sync job for resilience
- Optional: Account provisioning in Click2Run Auth

**Testing Checklist:**
- [ ] Webhook receives events from Click2Run Auth
- [ ] User created event provisions user in Chatwoot
- [ ] Role update event changes AccountUser role
- [ ] Periodic sync job runs without errors
- [ ] Webhook signature verification works

---

### Phase 5: Testing & Documentation (Week 6)

**Objective:** Comprehensive testing and documentation

#### Task 5.1: Integration Testing

**Test Scenarios:**
1. **First-time login:**
   - User exists in Click2Run Auth, not in Chatwoot
   - User record created
   - Organizations synced
   - Roles assigned correctly
   - Session created

2. **Returning user login:**
   - User exists in both systems
   - Profile updated if changed
   - Organizations re-synced
   - Session created

3. **Multi-organization membership:**
   - User belongs to multiple Click2Run Auth orgs
   - Multiple AccountUser records created
   - Can switch between accounts in Chatwoot

4. **Role changes:**
   - User promoted from member to owner in Click2Run Auth
   - AccountUser role updated to administrator
   - Permissions reflect new role

5. **User removal:**
   - User removed from Click2Run Auth org
   - AccountUser record deleted
   - User loses access to that account

6. **Error scenarios:**
   - Invalid JWT token → Unauthorized error
   - Click2Run Auth API down → Graceful degradation
   - Webhook signature mismatch → Rejected
   - Sync failures → Logged and retried

#### Task 5.2: Documentation

**File:** `.codi/CLICK2RUN_SETUP_GUIDE.md`

**Contents:**
- Click2Run Auth tenant setup instructions
- Application configuration
- Organization and role setup
- Environment variable reference
- Troubleshooting guide

**File:** `.codi/ARCHITECTURE.md`

**Contents:**
- System architecture diagram
- Authentication flow diagram
- Data model relationships
- API integration points
- Security considerations

**File:** `README.md` (update)

Add section on Click2Run Auth authentication:
- Prerequisites
- Configuration steps
- Development setup
- Production deployment

#### Task 5.3: Security Audit

**Checklist:**
- [ ] JWT signature validation implemented
- [ ] Webhook signature verification implemented
- [ ] State parameter used for CSRF protection
- [ ] Secrets stored securely (environment variables)
- [ ] No client secrets exposed to frontend
- [ ] HTTPS enforced in production
- [ ] Token caching has reasonable TTL
- [ ] Session timeout configured
- [ ] Authorization checks still enforced (Pundit policies)

**Deliverables:**
- All test scenarios pass
- Documentation complete
- Security audit completed
- Ready for production deployment

---

## File Inventory

### New Files (9 files, ~450 lines total)

| File | Lines | Purpose |
|------|-------|---------|
| `lib/devise/strategies/click2run_authenticatable.rb` | ~80 | Custom Devise strategy for JWT validation |
| `app/services/click2run/organization_sync_service.rb` | ~100 | Sync organizations and roles from Click2Run Auth |
| `app/services/click2run/account_provisioning_service.rb` | ~60 | Optional: Create Click2Run Auth orgs from Chatwoot |
| `app/controllers/auth/click2run_controller.rb` | ~60 | OAuth2 callback handler |
| `app/controllers/webhooks/click2run_controller.rb` | ~80 | Webhook event handler |
| `app/jobs/click2run/sync_organizations_job.rb` | ~40 | Periodic sync job |
| `app/javascript/v3/views/login/Index.vue` | ~50 | Updated login page |
| `db/migrate/YYYYMMDDHHMMSS_add_click2run_fields.rb` | ~10 | Database migration |
| `.codi/CLICK2RUN_SETUP_GUIDE.md` | N/A | Setup documentation |

### Modified Files (3 files, ~20 lines total changes)

| File | Changes | Purpose |
|------|---------|---------|
| `config/initializers/devise.rb` | +5 lines | Register Click2Run Auth strategy |
| `config/routes.rb` | +5 lines | Add callback and webhook routes |
| `.env` | +6 lines | Add Click2Run Auth configuration |

### Unchanged (Core Chatwoot)

- ✅ `app/models/user.rb` - Minimal changes (still shadow records)
- ✅ `app/models/account.rb` - Only add `click2run_org_id` column
- ✅ `app/models/account_user.rb` - No changes
- ✅ `app/policies/*` - No changes (21 files)
- ✅ `lib/current.rb` - No changes
- ✅ All authorization logic unchanged

---

## Environment Variables Reference

### Required Variables

```bash
# Click2Run Auth Configuration
CLICK2RUN_ENDPOINT=https://your-tenant.click2run.app
CLICK2RUN_APP_ID=your_application_id
CLICK2RUN_APP_SECRET=your_application_secret
CLICK2RUN_REDIRECT_URI=http://localhost:3000/auth/click2run/callback

# Click2Run Auth Management API (for M2M access)
CLICK2RUN_M2M_APP_ID=your_m2m_app_id
CLICK2RUN_M2M_APP_SECRET=your_m2m_app_secret

# Optional: Webhook signing secret
CLICK2RUN_WEBHOOK_SECRET=your_webhook_signing_secret
```

### Frontend Variables (Vite)

```bash
VITE_CLICK2RUN_ENDPOINT=https://your-tenant.click2run.app
VITE_CLICK2RUN_APP_ID=your_application_id
```

---

## Click2Run Auth Configuration Checklist

### Application Setup

- [ ] Create Traditional Web Application in Click2Run Auth
- [ ] Configure redirect URIs (dev + production)
- [ ] Set allowed scopes: `openid`, `profile`, `email`, `organizations`
- [ ] Enable "Always issue Refresh Token"
- [ ] Configure token expiration (default: 2 weeks for refresh token)

### Organizations Setup

- [ ] Create initial organizations (mapped to Chatwoot Accounts)
- [ ] Define organization roles:
  - `owner` - Full administrative access
  - `admin` - Administrative access
  - `member` - Standard user access
- [ ] Assign users to organizations with appropriate roles

### Management API Setup

- [ ] Create Machine-to-Machine application
- [ ] Grant scopes: `read:users`, `read:organizations`, `read:organization_memberships`
- [ ] Store M2M credentials securely

### Webhook Setup (Optional but Recommended)

- [ ] Configure webhook endpoint URL
- [ ] Select events to receive:
  - `User.Created`
  - `User.Updated`
  - `User.Deleted`
  - `OrganizationMembership.Created`
  - `OrganizationMembership.Updated`
  - `OrganizationMembership.Deleted`
- [ ] Store webhook signing secret
- [ ] Test webhook delivery

---

## Deployment Checklist

### Pre-Deployment

- [ ] All tests passing
- [ ] Security audit completed
- [ ] Documentation reviewed
- [ ] Environment variables configured (staging)
- [ ] Database migration reviewed
- [ ] Rollback plan documented

### Deployment Steps

1. **Deploy to Staging:**
   - [ ] Run database migration
   - [ ] Deploy code changes
   - [ ] Verify authentication flow
   - [ ] Test organization sync
   - [ ] Test role mapping

2. **Production Deployment:**
   - [ ] Schedule maintenance window (if needed)
   - [ ] Backup database
   - [ ] Run database migration
   - [ ] Deploy code changes
   - [ ] Configure Click2Run Auth production application
   - [ ] Update redirect URIs to production URL
   - [ ] Test authentication flow
   - [ ] Monitor error logs

3. **Post-Deployment:**
   - [ ] Verify all users can authenticate
   - [ ] Check organization sync working
   - [ ] Monitor webhook events
   - [ ] Monitor periodic sync job
   - [ ] Review error logs

### Rollback Plan

If issues occur:

1. **Immediate Rollback:**
   ```bash
   git checkout main
   # Deploy previous version
   ```

2. **Database Rollback (if needed):**
   ```bash
   rails db:rollback
   ```

3. **Communication:**
   - Notify users of temporary login issues
   - Provide alternative access method (if available)

---

## Monitoring & Observability

### Key Metrics to Track

1. **Authentication Success Rate:**
   - Track successful vs. failed logins
   - Alert if success rate drops below 95%

2. **JWT Validation Performance:**
   - Monitor JWT decode time
   - Alert if p95 latency > 200ms

3. **Organization Sync Status:**
   - Track successful vs. failed syncs
   - Alert on repeated failures

4. **Webhook Delivery:**
   - Monitor webhook event processing
   - Alert on webhook signature failures

### Logging

**Important Events to Log:**

- User first login (provisioning)
- Organization sync completion
- Role changes
- Authentication failures
- Webhook event processing
- Sync job execution

**Log Format:**
```ruby
Rails.logger.info "[Click2Run Auth] User #{user.id} provisioned from Click2Run Auth ID #{click2run_uid}"
Rails.logger.info "[Click2Run Auth] Synced #{orgs.count} organizations for user #{user.id}"
Rails.logger.error "[Click2Run Auth] Failed to validate JWT: #{error.message}"
```

### Alerts

**Critical Alerts:**
- Authentication success rate < 95% for 5 minutes
- Click2Run Auth API unavailable (5xx errors)
- Webhook signature validation failures > 10 in 1 hour
- JWT validation failures > 100 in 1 hour

**Warning Alerts:**
- Organization sync failures > 5 in 1 hour
- Click2Run Auth API latency > 1 second (p95)
- Periodic sync job fails

---

## Troubleshooting Guide

### Issue: "Invalid Click2Run Auth token" error

**Symptoms:** Users cannot log in, see "Invalid token" error

**Causes:**
1. JWT signature validation failing
2. Click2Run Auth JWKS endpoint unreachable
3. Token expired
4. Wrong issuer validation

**Solutions:**
1. Check Click2Run Auth endpoint is accessible
2. Verify JWKS caching is working
3. Check system time is synchronized (NTP)
4. Verify `CLICK2RUN_ENDPOINT` matches issuer in JWT

### Issue: User created but organizations not synced

**Symptoms:** User can log in but has no AccountUser records

**Causes:**
1. Click2Run Auth Management API credentials invalid
2. User has no organization memberships in Click2Run Auth
3. Sync service error

**Solutions:**
1. Verify M2M credentials are correct
2. Check user's organization memberships in Click2Run Auth
3. Review sync service error logs
4. Manually trigger sync: `Click2Run Auth::OrganizationSyncService.new(user).sync_organizations`

### Issue: Webhook events not received

**Symptoms:** Organization changes in Click2Run Auth not reflected in Chatwoot

**Causes:**
1. Webhook URL not configured in Click2Run Auth
2. Firewall blocking Click2Run Auth webhooks
3. Webhook signature verification failing

**Solutions:**
1. Verify webhook URL in Click2Run Auth console
2. Check firewall/network settings
3. Verify `CLICK2RUN_WEBHOOK_SECRET` is correct
4. Test webhook endpoint manually with curl

### Issue: "Organization already exists" error

**Symptoms:** Sync fails with duplicate organization error

**Causes:**
1. Multiple Click2Run Auth orgs mapped to same Chatwoot Account
2. Race condition in sync process

**Solutions:**
1. Ensure `click2run_org_id` is unique in database
2. Add idempotency checks in sync service
3. Review organization mapping logic

---

## Migration Strategy (If Existing Users)

**Note:** Current plan assumes new deployment with no existing users. If migrating existing users:

### Option 1: Parallel Authentication (Recommended)

1. **Phase 1:** Deploy Click2Run Auth alongside existing auth
   - Feature flag: `CLICK2RUN_ENABLED=false`
   - Existing users continue using Chatwoot auth
   - New users use Click2Run Auth

2. **Phase 2:** User migration
   - Export existing users to Click2Run Auth
   - Match by email address
   - Send password reset emails (Click2Run Auth)

3. **Phase 3:** Cutover
   - Enable feature flag: `CLICK2RUN_ENABLED=true`
   - Disable Chatwoot native signup/login
   - All users use Click2Run Auth

### Option 2: Big Bang Migration

1. **Pre-migration:**
   - Export all users to Click2Run Auth
   - Create organizations in Click2Run Auth
   - Map roles

2. **Cutover:**
   - Deploy Click2Run Auth integration
   - Force all users to re-authenticate via Click2Run Auth
   - Disable Chatwoot native auth

**Risk:** Higher risk, requires coordinated deployment

---

## Success Criteria

### MVP (Minimum Viable Product)

- [ ] Users can authenticate via Click2Run Auth
- [ ] User records created in Chatwoot
- [ ] Organizations synced from Click2Run Auth
- [ ] Roles mapped correctly (owner → admin, member → agent)
- [ ] Users can access appropriate accounts
- [ ] Existing Chatwoot authorization works unchanged

### V1.0 (Production Ready)

- [ ] All MVP criteria met
- [ ] Webhook integration working
- [ ] Periodic sync job running
- [ ] Error handling robust
- [ ] Monitoring and alerting configured
- [ ] Documentation complete
- [ ] Security audit passed

### Future Enhancements

- [ ] Profile sync (name, avatar changes)
- [ ] Real-time role updates (via websockets)
- [ ] Self-service organization creation
- [ ] Custom role mapping (Enterprise)
- [ ] SSO configuration via Click2Run Auth connectors
- [ ] MFA enforcement policies

---

## References

### Documentation

- [Click2Run Auth Documentation](https://docs.click2run.io/)
- [Click2Run Auth SDK](https://docs.click2.run)
- [Devise Documentation](https://github.com/heartcombo/devise)
- [Pundit Authorization](https://github.com/varvet/pundit)

### API Endpoints

- **Click2Run Auth OIDC Discovery:** `https://your-tenant.click2run.app/oidc/.well-known/openid-configuration`
- **Click2Run Auth JWKS:** `https://your-tenant.click2run.app/oidc/jwks`
- **Click2Run Auth Management API:** `https://your-tenant.click2run.app/api`

### Support

- **Click2Run Auth Community:** [Click2Run Support)
- **Click2Run Auth GitHub Issues:** [click2run-io/click2run](https://click2.run/support)

---

## Conclusion

This plan provides a clear path to integrate Click2Run Auth as the primary identity provider for Chatwoot while:

1. **Maintaining upstream compatibility** - Minimal code changes, isolated custom code
2. **Preserving authorization logic** - Pundit policies and multi-tenancy unchanged
3. **Enabling centralized identity** - Click2Run Auth as single source of truth
4. **Supporting gradual rollout** - Feature flags and phased deployment

**Total Effort:** 4-6 weeks
**Custom Code:** ~450 lines
**Risk Level:** Low (isolated changes, rollback capability)

**Next Step:** Begin Phase 1 - Click2Run Auth tenant setup
