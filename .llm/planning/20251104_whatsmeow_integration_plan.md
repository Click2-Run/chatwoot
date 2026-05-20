---
Created: 2025-11-04T05:10:00Z
Operation: Whatsmeow Integration Planning for Chatwoot
Context: Replace Baileys WhatsApp provider with Whatsmeow API integration
Related Files:
  - /root/data/development/chatwoot.git/app/services/whatsapp/providers/whatsapp_baileys_service.rb
  - /root/data/development/chatwoot.git/app/services/whatsapp/providers/base_service.rb
  - /root/data/development/click2run/delivery.git/whatsmeow/ (whatsmeow API)
---

# Chatwoot Whatsmeow Integration Plan

## Executive Summary

Integrate the fully-featured Whatsmeow API with Chatwoot as a new WhatsApp provider option. The Whatsmeow API has complete feature parity with Baileys and offers additional benefits including:

- **Production-ready Multi-Device Protocol** support
- **Better stability** and **active maintenance**
- **Built-in recovery mechanisms** (heartbeat, health checks, session recovery)
- **All P0, P1, and key P2 features** implemented
- **Comprehensive Swagger API documentation**

---

## Current State Analysis

### Existing Baileys Integration

**Location**: `app/services/whatsapp/providers/whatsapp_baileys_service.rb`

**Key Methods**:
1. `setup_channel_provider` - Create connection with phone number
2. `disconnect_channel_provider` - Disconnect connection
3. `send_message` - Send text/media/reaction messages
4. `toggle_typing_status` - Send typing/recording/paused indicators
5. `read_messages` - Mark messages as read
6. `get_profile_pic` - Get profile picture URL
7. `on_whatsapp` - Check if number is registered
8. `validate_provider_config?` - Validate API connection

**API Endpoints Used**:
```
POST   /connections/:phone → Create connection
DELETE /connections/:phone → Delete connection
POST   /connections/:phone/send-message → Send message
PATCH  /connections/:phone/presence → Update presence
POST   /connections/:phone/read-messages → Mark read
GET    /connections/:phone/profile-picture-url → Get profile pic
POST   /connections/:phone/on-whatsapp → Check registration
GET    /status/auth → Validate connection
```

**Configuration**:
- `BAILEYS_PROVIDER_DEFAULT_URL` - API base URL
- `BAILEYS_PROVIDER_DEFAULT_API_KEY` - API authentication key
- `BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME` - Client identifier

---

## Whatsmeow API Mapping

### URL Structure Comparison

**Baileys Pattern**: `/connections/:phone/...`
**Whatsmeow Pattern**: `/instances/:instance_id/...`

**Key Difference**: Whatsmeow uses `instance_id` (can be any unique identifier) instead of requiring phone number in URL path.

### Endpoint Mapping

| Baileys Endpoint | Whatsmeow Endpoint | Status | Notes |
|------------------|-------------------|--------|-------|
| `POST /connections/:phone` | `POST /instances` + `POST /instances/:id/connect` | ✅ Ready | Two-step process |
| `DELETE /connections/:phone` | `POST /instances/:id/disconnect` + `DELETE /instances/:id` | ✅ Ready | Optional disconnect first |
| `POST /connections/:phone/send-message` | `POST /instances/:id/messages/send/text` | ✅ Ready | Text messages |
| | `POST /instances/:id/messages/send/media` | ✅ Ready | Media messages |
| | `POST /instances/:id/messages/send/reaction` | ✅ Ready | Reactions |
| | `POST /instances/:id/messages/send/location` | ✅ Ready | Locations |
| `PATCH /connections/:phone/presence` | `PATCH /instances/:id/presence` | ✅ Ready | Same body format |
| `POST /connections/:phone/read-messages` | `POST /instances/:id/messages/mark-read` | ✅ Ready | Different field names |
| `GET /connections/:phone/profile-picture-url` | `GET /instances/:id/profile-picture/:jid` | ✅ Ready | JID in path |
| `POST /connections/:phone/on-whatsapp` | `GET /instances/:id/on_whatsapp/:phone` | ✅ Ready | GET instead of POST |
| `GET /status/auth` | `GET /instances/:id/status` | ✅ Ready | Returns connection status |
| `GET /media/:media_id` | `GET /instances/:id/media/:message_id` | ✅ Ready | Message ID instead of media ID |

---

## Implementation Strategy

### Option 1: Create New WhatsmeowService (Recommended)

**Pros**:
- Clean separation from Baileys
- Easier to maintain and test
- No risk of breaking existing Baileys integration
- Can coexist with Baileys for migration period

**Cons**:
- Slight code duplication (minimal, mostly HTTP calls)

**File**: `app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb`

### Option 2: Replace Baileys Service

**Pros**:
- No code duplication
- Single WhatsApp provider

**Cons**:
- Breaks existing Baileys users
- Risky migration
- No fallback option

**Recommendation**: **Option 1** - Create new service, deprecate Baileys gradually

---

## Implementation Plan

### Phase 1: Core Service Implementation (2-3 hours)

**Tasks**:
1. Create `whatsapp_whatsmeow_service.rb` based on Baileys service structure
2. Implement connection management methods:
   - `setup_channel_provider` (create instance + connect)
   - `disconnect_channel_provider` (disconnect + delete)
   - `validate_provider_config?` (check instance status)
3. Implement messaging methods:
   - `send_message` (text/media/reactions/location)
   - `media_url` (get media download URL)
4. Implement presence methods:
   - `toggle_typing_status` (composing/recording/paused)
5. Implement read receipt methods:
   - `read_messages` (mark as read)
6. Implement profile methods:
   - `get_profile_pic` (get profile picture URL)
   - `on_whatsapp` (check registration)

**Deliverable**: Functional `WhatsappWhatsmeowService` class

---

### Phase 2: Request/Response Adapters (1-2 hours)

**Tasks**:
1. Create request adapters to transform Chatwoot format → Whatsmeow format
2. Create response adapters to transform Whatsmeow format → Chatwoot format
3. Handle differences:
   - Baileys: `keys: [{id, remoteJid, fromMe}]`
   - Whatsmeow: `messages: [{id, remote_jid, from_me}]`
4. Phone number formatting:
   - Chatwoot: `+1234567890` or `1234567890`
   - Whatsmeow: `1234567890@s.whatsapp.net`

**Deliverable**: Clean adapter methods for format conversion

---

### Phase 3: Configuration & Environment (30 min)

**Tasks**:
1. Add environment variables:
   - `WHATSMEOW_PROVIDER_DEFAULT_URL` (e.g., `http://localhost:8080/api/v1/whatsmeow`)
   - `WHATSMEOW_PROVIDER_DEFAULT_API_KEY` (tenant API key)
2. Update channel provider configuration in Chatwoot admin panel
3. Document configuration options

**Deliverable**: Environment variables configured

---

### Phase 4: Testing & Validation (2-3 hours)

**Tasks**:
1. Unit tests for `WhatsappWhatsmeowService`
2. Integration tests with live Whatsmeow API
3. Test all message types:
   - Text messages
   - Media messages (image, video, audio, document)
   - Reactions
   - Location messages
   - Typing indicators
   - Read receipts
4. Test edge cases:
   - Connection failures
   - Reconnection after disconnect
   - Invalid phone numbers
   - Rate limiting

**Deliverable**: Comprehensive test suite

---

### Phase 5: Documentation & Migration Guide (1 hour)

**Tasks**:
1. Create migration guide for Baileys → Whatsmeow
2. Update Chatwoot documentation
3. Add troubleshooting guide
4. Document new features available in Whatsmeow

**Deliverable**: Complete documentation

---

## Technical Specifications

### Instance ID Strategy

**Problem**: Whatsmeow uses `instance_id`, Chatwoot uses `phone_number` as identifier

**Solution Options**:

1. **Use phone number as instance_id** (Recommended)
   - Simple mapping
   - No additional fields needed
   - Example: `+12345678901234567890` → `12345678901234567890`

2. **Use channel ID as instance_id**
   - Unique per channel
   - More flexible
   - Requires storing mapping

**Recommendation**: Option 1 - use normalized phone number (digits only) as instance_id

---

### JID Formatting

**Whatsmeow Requirement**: All operations need JID format (`number@s.whatsapp.net`)

**Helper Method**:
```ruby
def format_jid(phone_number)
  "#{phone_number.delete('+')}@s.whatsapp.net"
end
```

**Usage**:
- Contact operations: user JID
- Group operations: group JID (`123456@g.us`)

---

### Message Sending Differences

#### Baileys Format
```json
{
  "jid": "1234567890@s.whatsapp.net",
  "messageContent": {
    "text": "Hello",
    "image": "base64...",
    "react": {"key": {...}, "text": "👍"}
  }
}
```

#### Whatsmeow Format

**Text**:
```json
{
  "to": "1234567890@s.whatsapp.net",
  "message": "Hello",
  "quoted_message_id": "optional"
}
```

**Media**:
```json
{
  "to": "1234567890@s.whatsapp.net",
  "media_type": "image/png",
  "media_data": "base64...",
  "caption": "Caption",
  "filename": "image.png"
}
```

**Reaction**:
```json
{
  "to": "1234567890@s.whatsapp.net",
  "message_id": "3EB0ABC...",
  "emoji": "👍"
}
```

---

### Read Receipts Differences

#### Baileys Format
```json
{
  "keys": [
    {
      "id": "3EB0ABC...",
      "remoteJid": "1234567890@s.whatsapp.net",
      "fromMe": false
    }
  ]
}
```

#### Whatsmeow Format
```json
{
  "messages": [
    {
      "id": "3EB0ABC...",
      "remote_jid": "1234567890@s.whatsapp.net",
      "from_me": false
    }
  ]
}
```

**Adapter**:
```ruby
def format_read_messages(messages)
  {
    messages: messages.map do |msg|
      {
        id: msg.source_id,
        remote_jid: format_jid(phone_number),
        from_me: msg.message_type == 'outgoing'
      }
    end
  }
end
```

---

## Error Handling Strategy

### Connection Errors

**Baileys Behavior**: Raises `ProviderUnavailableError`

**Whatsmeow Behavior**: Returns HTTP error codes
- `401` - Invalid API key
- `404` - Instance not found
- `500` - Internal server error

**Implementation**:
```ruby
def process_response(response)
  case response.code
  when 200..299
    true
  when 401
    Rails.logger.error "Whatsmeow authentication failed"
    raise ProviderUnavailableError, 'Invalid API key'
  when 404
    Rails.logger.error "Whatsmeow instance not found"
    raise ProviderUnavailableError, 'Instance not found'
  else
    Rails.logger.error response.body
    false
  end
end
```

### Auto-Reconnection

**Strategy**: Same as Baileys
- Detect connection failure
- Call `handle_channel_error`
- Attempt `setup_channel_provider` again

**Implementation**: Use existing `with_error_handling` pattern

---

## Configuration Template

### Environment Variables

```bash
# Whatsmeow API Configuration
WHATSMEOW_PROVIDER_DEFAULT_URL=http://localhost:8080/api/v1/whatsmeow
WHATSMEOW_PROVIDER_DEFAULT_API_KEY=your-tenant-api-key-here

# Optional: Override per channel in admin panel
# Each channel can have custom:
# - provider_url
# - api_key
```

### Chatwoot Admin Panel

**Channel Configuration Fields**:
- `provider_url` - Whatsmeow API base URL (default from env)
- `api_key` - Tenant API key for authentication (default from env)
- `webhook_verify_token` - Token for webhook verification (auto-generated)

---

## Migration Path

### For New Installations

1. Set `WHATSMEOW_PROVIDER_DEFAULT_URL` and `WHATSMEOW_PROVIDER_DEFAULT_API_KEY`
2. Create WhatsApp channel in Chatwoot
3. Select "Whatsmeow" as provider
4. Scan QR code
5. Start receiving/sending messages

### For Existing Baileys Users

**Option A: Side-by-Side** (Recommended)
1. Keep Baileys channels running
2. Create new Whatsmeow channels for new numbers
3. Gradually migrate users to Whatsmeow
4. Deprecate Baileys after migration complete

**Option B: In-Place Migration** (Advanced)
1. Export Baileys session data
2. Import to Whatsmeow API
3. Update channel configuration to use Whatsmeow
4. No QR scan required (session preserved)

---

## Testing Checklist

### Unit Tests
- [ ] Connection setup/teardown
- [ ] Send text message
- [ ] Send media message
- [ ] Send reaction
- [ ] Send location
- [ ] Toggle typing status
- [ ] Mark messages as read
- [ ] Get profile picture
- [ ] Check WhatsApp registration
- [ ] Error handling
- [ ] Response parsing

### Integration Tests
- [ ] Create channel and scan QR
- [ ] Receive incoming message
- [ ] Send outgoing message
- [ ] Send media attachment
- [ ] React to message
- [ ] Mark message as read
- [ ] See typing indicator
- [ ] Connection recovery after disconnect
- [ ] Multiple channels simultaneously

### Edge Cases
- [ ] Invalid phone number
- [ ] Non-WhatsApp number
- [ ] Disconnected instance
- [ ] API server down
- [ ] Rate limiting
- [ ] Large media files
- [ ] Group messages
- [ ] Privacy-restricted profile pictures

---

## Success Criteria

### Functional Requirements
✅ All Baileys features working in Whatsmeow
✅ No breaking changes to Chatwoot UI/UX
✅ Same or better performance than Baileys
✅ Reliable reconnection after failures
✅ Comprehensive error messages

### Non-Functional Requirements
✅ Code follows Chatwoot conventions
✅ Comprehensive test coverage (>80%)
✅ Clear documentation for setup
✅ Migration guide for Baileys users
✅ No security vulnerabilities

---

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Core Service | 2-3 hours | Whatsmeow API running |
| Phase 2: Adapters | 1-2 hours | Phase 1 complete |
| Phase 3: Configuration | 30 min | Phase 1 complete |
| Phase 4: Testing | 2-3 hours | Phases 1-3 complete |
| Phase 5: Documentation | 1 hour | Phase 4 complete |
| **Total** | **7-10 hours** | |

---

## Risks & Mitigations

### Risk 1: API Incompatibility
**Likelihood**: Low
**Impact**: High
**Mitigation**: Comprehensive testing, adapter layer for format differences

### Risk 2: Performance Issues
**Likelihood**: Low
**Impact**: Medium
**Mitigation**: Load testing, connection pooling, rate limiting

### Risk 3: Webhook Delivery Failures
**Likelihood**: Medium
**Impact**: Medium
**Mitigation**: Implement retry logic, monitor webhook logs

### Risk 4: Session Management
**Likelihood**: Low
**Impact**: High
**Mitigation**: Use Whatsmeow's built-in session persistence, regular health checks

---

## Next Steps

1. **Immediate**: Create `whatsapp_whatsmeow_service.rb` skeleton
2. **Next**: Implement core methods (setup, send, disconnect)
3. **Then**: Add adapters for format conversion
4. **Finally**: Test with live Whatsmeow API

---

## References

- **Whatsmeow API**: `/root/data/development/click2run/delivery.git/whatsmeow/`
- **Whatsmeow Swagger**: `http://localhost:8080/api/v1/whatsmeow/docs/index.html`
- **Baileys Service**: `app/services/whatsapp/providers/whatsapp_baileys_service.rb`
- **Base Service**: `app/services/whatsapp/providers/base_service.rb`
- **Whatsmeow Implementation Docs**: `/root/data/development/click2run/delivery.git/whatsmeow/.llm/implementation/`

---

**Document Status**: READY FOR IMPLEMENTATION
**Last Updated**: 2025-11-04T05:10:00Z
**Author**: Claude Code (Anthropic)
**Version**: 1.0
