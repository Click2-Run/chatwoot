---
Created: 2025-11-04T14:00:00Z
Operation: Explanation of Z-API WhatsApp provider
Context: User found Z-API feature flag enabled but not seeing provider in UI, confused about Z-API mentions in Baileys component
Related Files:
  - config/features.yml:225-227
  - app/javascript/dashboard/routes/dashboard/settings/inbox/channels/BaileysWhatsapp.vue:91-117
  - app/javascript/dashboard/routes/dashboard/settings/inbox/channels/ZapiWhatsapp.vue
  - app/services/whatsapp/providers/whatsapp_zapi_service.rb
  - app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue:75-82
---

# Z-API WhatsApp Provider Explanation

## What is Z-API?

**Z-API is a Brazilian commercial WhatsApp API service** - similar to Baileys and Whatsmeow, but offered as a paid SaaS platform.

### Key Characteristics

**Service Type:** Unofficial WhatsApp API (like Baileys, Whatsmeow)
**Business Model:** Commercial SaaS with monthly subscription
**Target Market:** Brazilian businesses (payments in BRL - Brazilian Real)
**Tech Stack:** Uses WhatsApp Web protocol (same as Baileys)
**Hosting:** Managed service (they host the instances)

### Comparison with Other Providers

| Provider | Type | Hosting | Cost | Stability | Setup |
|----------|------|---------|------|-----------|-------|
| **WhatsApp Cloud** | Official | Meta | Free tier + pay-per-message | ⭐⭐⭐⭐⭐ | Complex |
| **Twilio** | Official | Twilio | Pay-per-message | ⭐⭐⭐⭐⭐ | Complex |
| **Baileys** | Unofficial | Self-hosted | Free (DIY) | ⭐⭐⭐ | Technical |
| **Whatsmeow** | Unofficial | Self-hosted | Free (DIY) | ⭐⭐⭐⭐ | Technical |
| **Z-API** | Unofficial | Managed (z-api.io) | ~$19/month | ⭐⭐⭐⭐ | Simple |

---

## Why Z-API Exists in Chatwoot

### Market Need

**Problem:**
- WhatsApp Cloud/Twilio: Complex setup, business verification, Meta approval process
- Baileys/Whatsmeow: Requires technical skills, self-hosting, maintenance

**Solution:**
- Z-API: Managed service, simple setup, no hosting required
- Target: Small businesses in Brazil wanting "easy WhatsApp integration"

### Chatwoot Partnership

**Affiliate Agreement:** Chatwoot has an affiliate link with Z-API

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/ZapiWhatsapp.vue:27-28`

```javascript
const zapiAffiliateUrl =
  'https://app.z-api.io/app/auth/new-account?afilliate=3E0B31343E6CB0297B567AC1D8277FBB';
```

**Revenue Model:**
- Chatwoot gets 10% commission on Z-API subscriptions via affiliate link
- Users get 10% discount when signing up via Chatwoot link
- Win-win: User saves money, Chatwoot earns referral fee

---

## Why You're Not Seeing Z-API

### Current Feature Flag Status

**File:** `config/features.yml:225-227`

```yaml
- name: channel_zapi
  display_name: Z-API Channel
  enabled: true  # ← You set this to true
```

**BUT:** This only changes the DEFAULT for **NEW accounts**.

### How Feature Flags Work in Chatwoot

1. **Global Default** (`features.yml`): Default setting for new accounts
2. **Per-Account Setting** (`accounts.feature_flags` column): Individual account overrides

**What Happened:**
```
1. You changed features.yml: enabled: false → enabled: true
2. This affects NEW accounts created AFTER the change
3. Your EXISTING account still has the flag set to FALSE in database
```

### Check Your Account Status

**Rails Console:**
```ruby
account = Account.find_by(id: YOUR_ACCOUNT_ID)
account.feature_enabled?(:channel_zapi)  # => false (probably)
```

### Enable Z-API for Your Account

**Option 1: Rails Console**
```ruby
account = Account.find(YOUR_ACCOUNT_ID)
account.enable_features!(:channel_zapi)
account.feature_enabled?(:channel_zapi)  # => true

# Refresh browser, Z-API should appear now
```

**Option 2: Database Direct**
```sql
-- Check current flags
SELECT id, name, feature_flags FROM accounts WHERE id = YOUR_ACCOUNT_ID;

-- Z-API is flag position 44 (last in list)
-- Set bit 44 to 1
UPDATE accounts
SET feature_flags = feature_flags | (1 << 43)  -- 0-indexed, so position 44 = bit 43
WHERE id = YOUR_ACCOUNT_ID;
```

**Option 3: Super Admin UI (if you have access)**
- Navigate to Super Admin → Accounts
- Select your account
- Toggle "Z-API Channel" feature flag

---

## Why Baileys Component Mentions Z-API

### Cross-Sell Banner

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/BaileysWhatsapp.vue:103-117`

```vue
<div
  v-if="isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_ZAPI)"
  class="w-full mb-6"
>
  <PromoBanner
    :title="$t('INBOX_MGMT.ADD.WHATSAPP.ZAPI_PROMO.SWITCH_BANNER.TITLE')"
    :description="
      $t('INBOX_MGMT.ADD.WHATSAPP.ZAPI_PROMO.SWITCH_BANNER.DESCRIPTION')
    "
    variant="info"
    logo-src="/assets/images/dashboard/channels/z-api/z-api-dark-blue.png"
    logo-alt="Z-API"
    :cta-text="$t('INBOX_MGMT.ADD.WHATSAPP.ZAPI_PROMO.SWITCH_BANNER.CTA')"
    @cta-click="switchToZapi"
  />
</div>
```

**Purpose:** Cross-sell Z-API to users setting up Baileys

**Translation:** `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json:354-356`

```json
{
  "SWITCH_BANNER": {
    "TITLE": "Consider switching to Z-API for easier setup",
    "DESCRIPTION": "Z-API provides a more stable connection than Baileys and requires less configuration than Cloud/Twilio. Switch to a hassle-free WhatsApp integration.",
    "CTA": "Switch to Z-API"
  }
}
```

**Marketing Strategy:**
1. User selects Baileys (free but technical)
2. Banner appears: "Want easier setup? Try Z-API!"
3. User clicks → redirected to Z-API setup page
4. User signs up via affiliate link → Chatwoot earns commission

**Only Shows If:**
- `channel_zapi` feature flag enabled for account
- User is on Baileys setup page

---

## Z-API Setup Flow

### 1. Provider Selection

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue:75-82`

```javascript
if (isFeatureFlagEnabled(FEATURE_FLAGS.CHANNEL_ZAPI)) {
  providers.push({
    key: PROVIDER_TYPES.ZAPI,
    title: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.ZAPI'),
    description: t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.ZAPI_DESC'),
    icon: 'i-woot-zapi',
  });
}
```

**User sees:** "Z-API - Connect via non-official API Z-API"

### 2. Z-API Configuration Form

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/ZapiWhatsapp.vue`

**Required Fields:**
1. **Inbox Name** - Display name in Chatwoot
2. **Phone Number** - WhatsApp number (E.164 format: +5511999999999)
3. **Instance ID** - From Z-API dashboard (password field)
4. **Token** - From Z-API dashboard (password field)
5. **Security Token** (Client Token) - From Z-API dashboard (password field)

**Affiliate Banner at Top:**
```vue
<PromoBanner
  title="Get 10% off your Z-API subscription"
  description="Create your Z-API account using our affiliate link..."
  cta-text="Create Z-API Account"
  cta-link="https://app.z-api.io/app/auth/new-account?afilliate=..."
/>
```

### 3. Backend Service

**File:** `app/services/whatsapp/providers/whatsapp_zapi_service.rb`

**API Base:** `https://api.z-api.io`

**Key Methods:**
- `setup_channel_provider` - Configures webhooks on Z-API side
- `send_message` - Sends WhatsApp messages via Z-API API
- `qr_code_image` - Fetches QR code for device linking
- `disconnect_channel_provider` - Logs out from Z-API

**Webhook Configuration:**
```ruby
def setup_channel_provider
  response = HTTParty.put(
    "#{api_instance_path_with_token}/update-every-webhooks",
    headers: api_headers,
    body: {
      value: whatsapp_channel.inbox.callback_webhook_url,
      notifySentByMe: true
    }.to_json
  )

  # Trigger QR code polling if not connected
  Channels::Whatsapp::ZapiQrCodeJob.perform_later(whatsapp_channel)
    if whatsapp_channel.provider_connection['connection'] == 'close'
end
```

### 4. QR Code Polling

**File:** `app/jobs/channels/whatsapp/zapi_qr_code_job.rb`

**Why Polling:**
- Z-API doesn't push QR codes via webhook
- Chatwoot polls every 30 seconds for new QR code
- Max 3 attempts (90 seconds timeout)

**Similar to Baileys** but different API endpoints

---

## Z-API vs Baileys vs Whatsmeow

### Technical Architecture

| Aspect | Baileys | Whatsmeow | Z-API |
|--------|---------|-----------|-------|
| **Protocol** | WhatsApp Web | WhatsApp Multi-Device | WhatsApp Web |
| **Language** | Node.js | Go | Unknown (SaaS) |
| **Hosting** | Self-hosted | Self-hosted | Managed (z-api.io) |
| **Instance Management** | DIY API server | DIY API server | Z-API handles it |
| **QR Code** | Generated locally | Generated locally | Fetched from Z-API |
| **Webhooks** | Configured by user | Configured by user | Configured by Z-API |
| **Auth Storage** | Local filesystem | Local database | Z-API servers |

### Cost Comparison

**Baileys:**
- API: Free (open source)
- Hosting: ~$5-20/month (VPS/server)
- Maintenance: Your time/effort
- **Total:** $5-20/month + time

**Whatsmeow:**
- API: Free (open source)
- Hosting: ~$5-20/month (VPS/server)
- Maintenance: Your time/effort
- **Total:** $5-20/month + time

**Z-API:**
- API: Included
- Hosting: Included
- Maintenance: Included
- **Total:** ~$19/month (all-inclusive)

### When to Choose Each

**Choose Baileys/Whatsmeow if:**
- You have technical skills
- You want full control
- You prefer self-hosting
- Budget is tight (free is better)

**Choose Z-API if:**
- You want "plug and play" solution
- No technical skills
- Prefer managed service
- Budget allows ~$19/month
- Located in Brazil (support in Portuguese)

**Choose WhatsApp Cloud/Twilio if:**
- You need official API
- Business verification approved
- High volume (pay per message cheaper at scale)
- Require guaranteed uptime/SLA

---

## Configuration Details

### Z-API Provider Config Structure

**Database Storage:** `channel_whatsapp.provider_config`

```json
{
  "instance_id": "3E0B31343E6CB0297B567AC1D8277FBB",
  "token": "ABC123TOKEN",
  "client_token": "XYZ789SECURITY",
  "webhook_verify_token": "generated_by_chatwoot"
}
```

### Z-API API Endpoints Used

**Base URL:** `https://api.z-api.io`

**Instance Path:** `/instances/{instance_id}`

**Endpoints:**
```
GET  /instances/{id}/status                  - Check connection status
PUT  /instances/{id}/update-every-webhooks   - Configure webhook URL
GET  /instances/{id}/qr-code/image           - Fetch QR code
GET  /instances/{id}/disconnect              - Logout device
POST /instances/{id}/send-text               - Send text message
POST /instances/{id}/send-image              - Send image
POST /instances/{id}/read-message            - Mark as read
GET  /instances/{id}/check-number-status     - Check if on WhatsApp
```

**Authentication:**
- Header: `client-token: {client_token}`
- Query params: `?token={token}`

### Example API Call

```ruby
# Send text message
HTTParty.post(
  "https://api.z-api.io/instances/ABC123/send-text",
  headers: {
    'client-token' => 'XYZ789SECURITY',
    'Content-Type' => 'application/json'
  },
  body: {
    phone: '5511999999999',
    message: 'Hello from Chatwoot!'
  }.to_json
)
```

---

## Why Z-API Cross-Sell in Baileys

### Business Strategy

**Problem Chatwoot Solves:**
- Users choose Baileys (free) but struggle with setup
- Technical complexity → bad user experience
- Abandoned setups → lost potential customers

**Solution:**
- Show Z-API banner during Baileys setup
- Offer "easier alternative" at critical moment
- User pays for convenience → Chatwoot earns commission

### UX Psychology

**Timing:** Banner shows DURING Baileys setup (not before)

**Why This Works:**
1. User already committed to WhatsApp integration
2. User facing technical complexity (API keys, URLs, hosting)
3. Banner offers "escape hatch" - easier path
4. 10% discount creates urgency
5. Affiliate link tracked → Chatwoot gets paid

**Conversion Funnel:**
```
1. User selects "Baileys" (free option)
2. Sees form: API Key, Provider URL, Advanced options
3. Banner appears: "Too complicated? Try Z-API!"
4. User clicks "Switch to Z-API"
5. Redirected to Z-API form (simpler, managed)
6. Banner shows affiliate link: "Get 10% off"
7. User signs up via affiliate → Chatwoot earns commission
8. User completes setup → happy customer
```

### Revenue Model

**For Chatwoot:**
- Earn ~$2/month per Z-API user (10% of $19)
- Zero cost (no hosting, no support)
- Passive income from referrals

**For User:**
- Save 10% on Z-API subscription
- Get easier setup experience
- Worth paying for convenience

**For Z-API:**
- Gain customers via Chatwoot ecosystem
- Pay 10% affiliate fee (customer acquisition cost)
- Better than traditional marketing

**Win-Win-Win scenario**

---

## How to Fully Enable Z-API

### Step 1: Enable Feature Flag

**Rails Console:**
```ruby
# Find your account
account = Account.find_by(name: 'Your Account Name')

# Or by ID
account = Account.find(1)

# Enable Z-API
account.enable_features!(:channel_zapi)

# Verify
account.feature_enabled?(:channel_zapi)  # => true
```

### Step 2: Refresh Browser

Hard refresh (Ctrl+Shift+R / Cmd+Shift+R) to clear cache

### Step 3: Navigate to Inbox Creation

Settings → Inboxes → Add Inbox → WhatsApp

**You should now see:**
- WhatsApp Cloud
- Twilio
- Baileys (with Z-API banner inside)
- Whatsmeow
- **Z-API** ← NEW!

### Step 4: Select Z-API

Click Z-API provider card

### Step 5: Create Z-API Account (if needed)

1. Click green banner "Create Z-API Account"
2. Redirected to `https://app.z-api.io/app/auth/new-account?afilliate=...`
3. Sign up with email/password
4. Choose plan (~$19/month)
5. Get 10% discount via affiliate link

### Step 6: Get Credentials from Z-API Dashboard

**Z-API Dashboard → Instances → Your Instance**

Copy these values:
- Instance ID (e.g., `3E0B31343E6CB0297B567AC1D8277FBB`)
- Token (e.g., `ABC123TOKEN456`)
- Security Token (Security tab → Client Token)

### Step 7: Complete Chatwoot Setup

**Paste credentials into form:**
- Inbox Name: "My WhatsApp"
- Phone Number: +5511999999999 (your WhatsApp number)
- Instance ID: (paste from Z-API)
- Token: (paste from Z-API)
- Security Token: (paste from Z-API)

**Submit → Success!**

### Step 8: Link Device (QR Code)

After creation, Chatwoot will:
1. Configure webhooks on Z-API
2. Fetch QR code from Z-API
3. Display QR code in modal
4. Scan with WhatsApp app
5. Connection established!

---

## Troubleshooting

### "I enabled the feature flag but don't see Z-API"

**Cause:** Feature flag not enabled for YOUR account (only affects new accounts)

**Fix:** Run Rails console command to enable for existing account (see Step 1 above)

### "Z-API option disappeared after I created inbox"

**Cause:** Feature flag was disabled or cache issue

**Fix:**
1. Check feature flag: `account.feature_enabled?(:channel_zapi)`
2. Hard refresh browser (Ctrl+Shift+R)
3. Check `config/features.yml` - don't set `enabled: false`

### "Baileys shows Z-API banner but Z-API not in provider list"

**Cause:** Z-API cross-sell is separate from provider visibility

**Fix:** Feature flag controls BOTH. If banner shows, provider should show. Check account-level flag.

### "Created Z-API inbox but QR code not appearing"

**Cause:** QR code polling job not running or Z-API API issue

**Fix:**
1. Check Sidekiq queue: `Channels::Whatsapp::ZapiQrCodeJob`
2. Check Z-API dashboard: Is instance active?
3. Check logs: `tail -f log/development.log | grep -i zapi`

---

## Summary

**What is Z-API?**
- Brazilian commercial WhatsApp API service
- Managed hosting (no self-hosting required)
- Simple setup compared to Baileys/Whatsmeow
- ~$19/month subscription

**Why in Chatwoot?**
- Affiliate partnership (Chatwoot earns commission)
- User gets 10% discount
- Alternative for non-technical users
- Cross-sell to Baileys users (easier option)

**Why not visible?**
- Feature flag enabled in `features.yml` only affects NEW accounts
- Existing accounts need manual flag enable via Rails console
- Check: `account.feature_enabled?(:channel_zapi)`
- Fix: `account.enable_features!(:channel_zapi)`

**Why mentioned in Baileys?**
- Cross-sell banner to promote easier alternative
- Shows during Baileys setup (when user struggling)
- Marketing strategy to convert free users to paid referrals
- Only shows if `channel_zapi` flag enabled
