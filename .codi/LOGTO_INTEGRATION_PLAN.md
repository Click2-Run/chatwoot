# Logto Integration Plan for Chatwoot

**Branch:** `codi-logto`
**Date:** 2025-11-04
**Status:** Planning Phase
**Estimated Timeline:** 4-6 weeks

---

## Executive Summary

This document outlines the plan to integrate Logto as the primary identity provider for Chatwoot while maintaining compatibility with upstream updates and preserving existing authorization logic.

### Approach: Official Logto SDK + Custom Devise Strategy

This hybrid approach provides:
- ✅ Centralized identity management across all applications
- ✅ Minimal divergence from upstream Chatwoot (upstream merge friendly)
- ✅ No migration complexity (new deployment)
- ✅ Maintainable custom code (~400 lines total)

---

## Architecture Overview

```
┌──────────────────────────────────────────┐
│  LOGTO (Primary Identity Provider)       │
│  - All applications use this             │
│  - User database, MFA, SSO, etc.         │
│  - Organizations = Chatwoot Accounts     │
└────────────┬─────────────────────────────┘
             │ OIDC/OAuth2 flow
             │ JWT tokens
             ▼
┌──────────────────────────────────────────┐
│  CHATWOOT (Consumer Application)         │
│                                           │
│  ┌────────────────────────────────────┐  │
│  │ Custom Devise Strategy              │  │
│  │ lib/devise/strategies/              │  │
│  │   logto_authenticatable.rb          │  │
│  │                                     │  │
│  │ - Validates Logto JWT               │  │
│  │ - Creates shadow User record        │  │
│  │ - No password, no Devise modules    │  │
│  └────────────┬───────────────────────┘  │
│               │                           │
│  ┌────────────▼───────────────────────┐  │
│  │ User Model (Minimal)                │  │
│  │ - email, name, provider='logto'     │  │
│  │ - uid (Logto user ID)               │  │
│  │ - NO password, NO MFA fields        │  │
│  │ - NO Devise modules (stripped down) │  │
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
- Chatwoot maintains lightweight User records synchronized from Logto
- Users authenticate via Logto, but Chatwoot needs local records for:
  - Foreign key relationships (AccountUser, Messages, etc.)
  - Session management
  - Authorization context (Current.user)

### 2. Organization Mapping
```
Logto Organization → Chatwoot Account
Logto Org Owner    → Chatwoot Administrator
Logto Org Member   → Chatwoot Agent
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

### Phase 1: Logto Setup (Week 1)

**Objective:** Configure Logto tenant and application

**Tasks:**
1. Create Logto Application (Traditional Web App)
2. Configure redirect URIs:
   - Development: `http://localhost:3000/auth/logto/callback`
   - Production: `https://your-domain.com/auth/logto/callback`
3. Set up scopes: `openid`, `profile`, `email`, `organizations`
4. Create initial organizations (mapped to Chatwoot Accounts)
5. Define organization roles:
   - `owner` → Maps to Chatwoot Administrator
   - `admin` → Maps to Chatwoot Administrator
   - `member` → Maps to Chatwoot Agent
6. Document Logto application credentials

**Deliverables:**
- Logto tenant configured
- Environment variables documented
- Test user accounts created in Logto

**Files Modified:**
- `.env` (add Logto configuration)

---

### Phase 2: Backend Integration (Week 2-3)

**Objective:** Implement Logto authentication strategy and user provisioning

#### Task 2.1: Custom Devise Strategy

**File:** `lib/devise/strategies/logto_authenticatable.rb` (~80 lines)

**Purpose:** Validates Logto JWT tokens and creates/finds shadow User records

**Key Features:**
- JWT signature validation using Logto's JWKS endpoint
- Automatic user provisioning on first login
- Token caching for performance
- Error handling for invalid/expired tokens

**Implementation Notes:**
- Strategy checks for Bearer token in Authorization header
- Decodes JWT and validates against Logto's public keys
- Creates User record with `provider: 'logto'` and `uid: claims['sub']`
- No password stored (authentication happens in Logto)

**Dependencies:**
- `jwt` gem (already in Gemfile)

#### Task 2.2: Logto Organization Sync Service

**File:** `app/services/logto/organization_sync_service.rb` (~100 lines)

**Purpose:** Synchronizes Logto organizations and user roles to Chatwoot

**Key Features:**
- Fetches user's organizations from Logto API
- Creates/updates Account records mapped to Logto orgs
- Creates/updates AccountUser records with correct roles
- Role mapping: owner/admin → administrator, member → agent

**API Requirements:**
- Logto Management API access (M2M token)
- Endpoint: `/api/users/{userId}/organizations`

**Implementation Notes:**
- Requires machine-to-machine (M2M) application in Logto
- Cache M2M tokens (1 hour TTL)
- Handle API errors gracefully
- Idempotent sync operations

#### Task 2.3: Callback Controller

**File:** `app/controllers/auth/logto_controller.rb` (~60 lines)

**Purpose:** Handles OAuth2 authorization code callback from Logto

**Flow:**
1. Receive authorization code from Logto
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

**File:** `db/migrate/YYYYMMDDHHMMSS_add_logto_fields.rb` (~10 lines)

**Changes:**
```ruby
# accounts table
add_column :accounts, :logto_org_id, :string
add_index :accounts, :logto_org_id, unique: true

# users table
add_column :users, :logto_synced_at, :datetime
```

**Purpose:**
- `logto_org_id`: Links Chatwoot Account to Logto Organization
- `logto_synced_at`: Tracks last sync timestamp for debugging

#### Task 2.5: Configuration Updates

**File:** `config/initializers/devise.rb` (+5 lines)

Add Logto strategy to Warden:
```ruby
config.warden do |manager|
  manager.strategies.add(:logto_authenticatable, Devise::Strategies::LogtoAuthenticatable)
  manager.default_strategies(scope: :user).unshift :logto_authenticatable
end
```

**File:** `config/routes.rb` (+3 lines)

Add callback route:
```ruby
namespace :auth do
  get 'logto/callback', to: 'logto#callback'
end
```

**Deliverables:**
- Custom Devise strategy implemented and tested
- Organization sync service functional
- Callback controller handling OAuth2 flow
- Database migration applied
- Configuration files updated

**Testing Checklist:**
- [ ] JWT validation works with Logto tokens
- [ ] User record created on first login
- [ ] Organizations synced correctly
- [ ] Roles mapped properly (owner → admin, member → agent)
- [ ] Callback flow completes without errors
- [ ] Session created successfully

---

### Phase 3: Frontend Integration (Week 4)

**Objective:** Replace Chatwoot login UI with Logto authentication

#### Task 3.1: Update Login Page

**File:** `app/javascript/v3/views/login/Index.vue` (~50 lines, complete replacement)

**Changes:**
- Remove password/email form
- Add "Sign in with Logto" button
- Implement OIDC authorization redirect
- Add state parameter for CSRF protection
- Store state in sessionStorage for validation

**Flow:**
1. User clicks "Sign in with Logto"
2. Generate random state
3. Store state in sessionStorage
4. Redirect to Logto authorization endpoint
5. Logto handles authentication (MFA, SSO, etc.)
6. Logto redirects back to callback URL with code

**OIDC Parameters:**
- `client_id`: Logto application ID
- `redirect_uri`: Callback URL
- `response_type`: code
- `scope`: openid profile email organizations
- `state`: Random CSRF token
- `prompt`: login (force fresh authentication)

#### Task 3.2: Environment Variables for Frontend

**File:** `.env` or Vite config

Add frontend-accessible variables:
```bash
VITE_LOGTO_ENDPOINT=https://your-tenant.logto.app
VITE_LOGTO_APP_ID=your_app_id
```

**Note:** Never expose `LOGTO_APP_SECRET` to frontend

#### Task 3.3: Remove Unused Login Routes (Optional)

**Files to potentially remove/update:**
- Password reset flow (now handled by Logto)
- Email confirmation flow (Logto handles verification)
- Social OAuth buttons (Google, SAML - migrate to Logto connectors)

**Recommendation:** Keep as fallback during migration, remove after stable

**Deliverables:**
- Login page redirects to Logto
- State parameter validation working
- Successful authentication redirects to dashboard
- Error handling for failed authentication

**Testing Checklist:**
- [ ] Login button redirects to Logto
- [ ] State parameter generated and validated
- [ ] Successful login redirects to dashboard
- [ ] Failed login shows error message
- [ ] MFA flow works (if enabled in Logto)
- [ ] SSO flow works (if configured in Logto)

---

### Phase 4: Organization Management (Week 5)

**Objective:** Implement bi-directional sync between Logto and Chatwoot

#### Task 4.1: Webhook Handler for Logto Events

**File:** `app/controllers/webhooks/logto_controller.rb` (~80 lines)

**Purpose:** Handle events from Logto (user created/updated, org membership changed)

**Supported Events:**
- `User.Created`: Provision new user in Chatwoot
- `User.Updated`: Sync user profile changes
- `User.Deleted`: Soft-delete or disable user
- `OrganizationMembership.Created`: Add user to Account
- `OrganizationMembership.Updated`: Update role
- `OrganizationMembership.Deleted`: Remove user from Account

**Security:**
- Verify webhook signature (Logto signing secret)
- Validate payload structure
- Idempotent processing (handle duplicate events)

**Implementation:**
```ruby
class Webhooks::LogtoController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_logto_signature

  def handle_event
    case params[:event]
    when 'User.Created'
      Logto::ProvisioningService.new.create_user(params[:data])
    when 'User.Updated'
      Logto::ProvisioningService.new.sync_user(params[:data])
    when 'OrganizationMembership.Updated'
      Logto::OrganizationSyncService.new.sync_membership(params[:data])
    end

    head :ok
  end

  private

  def verify_logto_signature
    # Verify webhook signature using signing secret
    # Implementation depends on Logto's webhook signature method
  end
end
```

**Routes:**
```ruby
post 'webhooks/logto', to: 'webhooks/logto#handle_event'
```

#### Task 4.2: Periodic Sync Job (Fallback)

**File:** `app/jobs/logto/sync_organizations_job.rb` (~40 lines)

**Purpose:** Periodic sync as fallback for webhook failures

**Schedule:** Run every 6 hours

**Implementation:**
```ruby
class Logto::SyncOrganizationsJob < ApplicationJob
  queue_as :default

  def perform
    User.where(provider: 'logto').find_each do |user|
      Logto::OrganizationSyncService.new(user).sync_organizations
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
  name: 'Logto Organization Sync',
  cron: '0 */6 * * *', # Every 6 hours
  class: 'Logto::SyncOrganizationsJob'
)
```

#### Task 4.3: Account Creation in Logto (Optional)

**File:** `app/services/logto/account_provisioning_service.rb` (~60 lines)

**Purpose:** Create Logto organizations when Chatwoot Accounts are created

**Use Case:** If admins create accounts in Chatwoot UI

**Implementation:**
```ruby
class Logto::AccountProvisioningService
  def create_organization(account)
    # Call Logto Management API to create org
    response = http_post("/api/organizations", {
      name: account.name,
      description: "Chatwoot Account: #{account.name}"
    })

    # Store Logto org ID
    account.update!(logto_org_id: response['id'])
  end
end
```

**Hook:** Add `after_create` callback to Account model

**Deliverables:**
- Webhook endpoint handling Logto events
- Periodic sync job for resilience
- Optional: Account provisioning in Logto

**Testing Checklist:**
- [ ] Webhook receives events from Logto
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
   - User exists in Logto, not in Chatwoot
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
   - User belongs to multiple Logto orgs
   - Multiple AccountUser records created
   - Can switch between accounts in Chatwoot

4. **Role changes:**
   - User promoted from member to owner in Logto
   - AccountUser role updated to administrator
   - Permissions reflect new role

5. **User removal:**
   - User removed from Logto org
   - AccountUser record deleted
   - User loses access to that account

6. **Error scenarios:**
   - Invalid JWT token → Unauthorized error
   - Logto API down → Graceful degradation
   - Webhook signature mismatch → Rejected
   - Sync failures → Logged and retried

#### Task 5.2: Documentation

**File:** `.codi/LOGTO_SETUP_GUIDE.md`

**Contents:**
- Logto tenant setup instructions
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

Add section on Logto authentication:
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
| `lib/devise/strategies/logto_authenticatable.rb` | ~80 | Custom Devise strategy for JWT validation |
| `app/services/logto/organization_sync_service.rb` | ~100 | Sync organizations and roles from Logto |
| `app/services/logto/account_provisioning_service.rb` | ~60 | Optional: Create Logto orgs from Chatwoot |
| `app/controllers/auth/logto_controller.rb` | ~60 | OAuth2 callback handler |
| `app/controllers/webhooks/logto_controller.rb` | ~80 | Webhook event handler |
| `app/jobs/logto/sync_organizations_job.rb` | ~40 | Periodic sync job |
| `app/javascript/v3/views/login/Index.vue` | ~50 | Updated login page |
| `db/migrate/YYYYMMDDHHMMSS_add_logto_fields.rb` | ~10 | Database migration |
| `.codi/LOGTO_SETUP_GUIDE.md` | N/A | Setup documentation |

### Modified Files (3 files, ~20 lines total changes)

| File | Changes | Purpose |
|------|---------|---------|
| `config/initializers/devise.rb` | +5 lines | Register Logto strategy |
| `config/routes.rb` | +5 lines | Add callback and webhook routes |
| `.env` | +6 lines | Add Logto configuration |

### Unchanged (Core Chatwoot)

- ✅ `app/models/user.rb` - Minimal changes (still shadow records)
- ✅ `app/models/account.rb` - Only add `logto_org_id` column
- ✅ `app/models/account_user.rb` - No changes
- ✅ `app/policies/*` - No changes (21 files)
- ✅ `lib/current.rb` - No changes
- ✅ All authorization logic unchanged

---

## Environment Variables Reference

### Required Variables

```bash
# Logto Configuration
LOGTO_ENDPOINT=https://your-tenant.logto.app
LOGTO_APP_ID=your_application_id
LOGTO_APP_SECRET=your_application_secret
LOGTO_REDIRECT_URI=http://localhost:3000/auth/logto/callback

# Logto Management API (for M2M access)
LOGTO_M2M_APP_ID=your_m2m_app_id
LOGTO_M2M_APP_SECRET=your_m2m_app_secret

# Optional: Webhook signing secret
LOGTO_WEBHOOK_SECRET=your_webhook_signing_secret
```

### Frontend Variables (Vite)

```bash
VITE_LOGTO_ENDPOINT=https://your-tenant.logto.app
VITE_LOGTO_APP_ID=your_application_id
```

---

## Logto Configuration Checklist

### Application Setup

- [ ] Create Traditional Web Application in Logto
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
   - [ ] Configure Logto production application
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
Rails.logger.info "[Logto] User #{user.id} provisioned from Logto ID #{logto_uid}"
Rails.logger.info "[Logto] Synced #{orgs.count} organizations for user #{user.id}"
Rails.logger.error "[Logto] Failed to validate JWT: #{error.message}"
```

### Alerts

**Critical Alerts:**
- Authentication success rate < 95% for 5 minutes
- Logto API unavailable (5xx errors)
- Webhook signature validation failures > 10 in 1 hour
- JWT validation failures > 100 in 1 hour

**Warning Alerts:**
- Organization sync failures > 5 in 1 hour
- Logto API latency > 1 second (p95)
- Periodic sync job fails

---

## Troubleshooting Guide

### Issue: "Invalid Logto token" error

**Symptoms:** Users cannot log in, see "Invalid token" error

**Causes:**
1. JWT signature validation failing
2. Logto JWKS endpoint unreachable
3. Token expired
4. Wrong issuer validation

**Solutions:**
1. Check Logto endpoint is accessible
2. Verify JWKS caching is working
3. Check system time is synchronized (NTP)
4. Verify `LOGTO_ENDPOINT` matches issuer in JWT

### Issue: User created but organizations not synced

**Symptoms:** User can log in but has no AccountUser records

**Causes:**
1. Logto Management API credentials invalid
2. User has no organization memberships in Logto
3. Sync service error

**Solutions:**
1. Verify M2M credentials are correct
2. Check user's organization memberships in Logto
3. Review sync service error logs
4. Manually trigger sync: `Logto::OrganizationSyncService.new(user).sync_organizations`

### Issue: Webhook events not received

**Symptoms:** Organization changes in Logto not reflected in Chatwoot

**Causes:**
1. Webhook URL not configured in Logto
2. Firewall blocking Logto webhooks
3. Webhook signature verification failing

**Solutions:**
1. Verify webhook URL in Logto console
2. Check firewall/network settings
3. Verify `LOGTO_WEBHOOK_SECRET` is correct
4. Test webhook endpoint manually with curl

### Issue: "Organization already exists" error

**Symptoms:** Sync fails with duplicate organization error

**Causes:**
1. Multiple Logto orgs mapped to same Chatwoot Account
2. Race condition in sync process

**Solutions:**
1. Ensure `logto_org_id` is unique in database
2. Add idempotency checks in sync service
3. Review organization mapping logic

---

## Migration Strategy (If Existing Users)

**Note:** Current plan assumes new deployment with no existing users. If migrating existing users:

### Option 1: Parallel Authentication (Recommended)

1. **Phase 1:** Deploy Logto alongside existing auth
   - Feature flag: `LOGTO_ENABLED=false`
   - Existing users continue using Chatwoot auth
   - New users use Logto

2. **Phase 2:** User migration
   - Export existing users to Logto
   - Match by email address
   - Send password reset emails (Logto)

3. **Phase 3:** Cutover
   - Enable feature flag: `LOGTO_ENABLED=true`
   - Disable Chatwoot native signup/login
   - All users use Logto

### Option 2: Big Bang Migration

1. **Pre-migration:**
   - Export all users to Logto
   - Create organizations in Logto
   - Map roles

2. **Cutover:**
   - Deploy Logto integration
   - Force all users to re-authenticate via Logto
   - Disable Chatwoot native auth

**Risk:** Higher risk, requires coordinated deployment

---

## Success Criteria

### MVP (Minimum Viable Product)

- [ ] Users can authenticate via Logto
- [ ] User records created in Chatwoot
- [ ] Organizations synced from Logto
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
- [ ] SSO configuration via Logto connectors
- [ ] MFA enforcement policies

---

## References

### Documentation

- [Logto Documentation](https://docs.logto.io/)
- [Logto Ruby SDK](https://github.com/logto-io/ruby)
- [Devise Documentation](https://github.com/heartcombo/devise)
- [Pundit Authorization](https://github.com/varvet/pundit)

### API Endpoints

- **Logto OIDC Discovery:** `https://your-tenant.logto.app/oidc/.well-known/openid-configuration`
- **Logto JWKS:** `https://your-tenant.logto.app/oidc/jwks`
- **Logto Management API:** `https://your-tenant.logto.app/api`

### Support

- **Logto Community:** [Discord](https://discord.gg/UEPaF3j5e6)
- **Logto GitHub Issues:** [logto-io/logto](https://github.com/logto-io/logto/issues)

---

## Conclusion

This plan provides a clear path to integrate Logto as the primary identity provider for Chatwoot while:

1. **Maintaining upstream compatibility** - Minimal code changes, isolated custom code
2. **Preserving authorization logic** - Pundit policies and multi-tenancy unchanged
3. **Enabling centralized identity** - Logto as single source of truth
4. **Supporting gradual rollout** - Feature flags and phased deployment

**Total Effort:** 4-6 weeks
**Custom Code:** ~450 lines
**Risk Level:** Low (isolated changes, rollback capability)

**Next Step:** Begin Phase 1 - Logto tenant setup
