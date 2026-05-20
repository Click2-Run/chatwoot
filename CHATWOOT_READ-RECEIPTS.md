  ✅ "Send Read Receipts" is FULLY IMPLEMENTED for Whatsmeow

  Here's the complete flow:

  ---
  Configuration

  UI Setting: "Send read receipts" checkbox (enabled by default)

  Stored as: channel.provider_config['mark_as_read']
  - nil or true → Send read receipts ✅
  - false → Don't send read receipts ❌

  ---
  Complete Flow

  ┌────────────────────────────────────────────────────────────────┐
  │                  READ RECEIPTS IMPLEMENTATION                   │
  └────────────────────────────────────────────────────────────────┘

  STEP 1: Agent Views Conversation
  ──────────────────────────────────────────────────────────────────
  Frontend (Agent opens conversation)
    │
    └─► POST /api/v1/accounts/{account_id}/conversations/{id}/update_last_seen
        (app/controllers/api/v1/accounts/conversations_controller.rb:112)
        │
        ├─► Updates conversation.agent_last_seen_at = DateTime.now
        │
        └─► dispatch_messages_read_event (line 216)
            └─► Dispatches event: MESSAGES_READ
                Payload: {
                  conversation: @conversation,
                  last_seen_at: @conversation.agent_last_seen_at
                }


  STEP 2: Event Listener Receives Event
  ──────────────────────────────────────────────────────────────────
  ChannelListener#messages_read
  (app/listeners/channel_listener.rb:32-44)
    │
    ├─► Gets conversation and channel
    │
    ├─► Checks: channel.respond_to?(:read_messages)? ✅
    │
    ├─► Finds unread incoming messages:
    │   messages = conversation.messages
    │     .where(message_type: :incoming)
    │     .where.not(status: :read)
    │     .where('updated_at > ?', last_seen_at)
    │
    └─► Calls: channel.read_messages(messages, conversation: conversation)


  STEP 3: Channel Model Delegates to Provider
  ──────────────────────────────────────────────────────────────────
  Channel::Whatsapp#read_messages
  (app/models/channel/whatsapp.rb:102-108)
    │
    ├─► Check provider supports read_messages? ✅
    │
    ├─► Check if disabled:
    │   if provider_config['mark_as_read'] == false
    │     return  # Skip sending read receipts
    │
    └─► Call: provider_service.read_messages(messages, phone_number: ...)


  STEP 4: Whatsmeow Service Sends API Call
  ──────────────────────────────────────────────────────────────────
  WhatsappWhatsmeowService#read_messages
  (app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb:233-258)
    │
    └─► POST {provider_url}/chatwoot/{account_id}/instances/{inbox_id}/messages/mark-read
        Headers: X-API-Key
        Body: {
          messages: [
            {
              id: "3EB0C0A3B0E5...",              // message.source_id
              remote_jid: "5511999999999@s.whatsapp.net",
              from_me: false                      // incoming message
            },
            // ... more messages
          ]
        }


  STEP 5: Delivery API Sends Read Receipts
  ──────────────────────────────────────────────────────────────────
  Whatsmeow Delivery API
    │
    ├─► Receives mark-read request
    │
    ├─► For each message:
    │   └─► Sends WhatsApp read receipt via protocol
    │
    └─► Returns: { status: "success" }


  RESULT: Customer sees blue checkmarks ✓✓ on WhatsApp
  ──────────────────────────────────────────────────────────────────

  ---
  Key Implementation Files

  | File                                                          | Lines            | Purpose                                                         |
  |---------------------------------------------------------------|------------------|-----------------------------------------------------------------|
  | app/controllers/api/v1/accounts/conversations_controller.rb   | 112-117, 214-218 | Triggers MESSAGES_READ event when agent views conversation      |
  | app/listeners/channel_listener.rb                             | 32-44            | Listens for MESSAGES_READ event and calls channel.read_messages |
  | app/models/channel/whatsapp.rb                                | 102-108          | Checks mark_as_read config and delegates to provider            |
  | app/services/whatsapp/providers/whatsapp_whatsmeow_service.rb | 233-258          | Makes API call to Delivery API to send read receipts            |

  ---
  Configuration Logic

  # app/models/channel/whatsapp.rb:102-108
  def read_messages(messages, conversation:)
    return unless provider_service.respond_to?(:read_messages)

    # NOTE: Default behavior is ENABLED (nil = true)
    return if provider_config&.dig('mark_as_read') == false

    provider_service.read_messages(messages, phone_number: conversation.contact.phone_number)
  end

  Behavior:
  - mark_as_read: nil → ✅ Send receipts (DEFAULT)
  - mark_as_read: true → ✅ Send receipts
  - mark_as_read: false → ❌ Don't send receipts

  ---
  When Read Receipts Are Sent

  ✅ Agent opens/views conversation → All unread incoming messages marked as read

  ✅ Agent switches between conversations → Previous conversation's messages marked as read

  ❌ Message just arrives → Not automatically marked as read (waits for agent to view)

  ---
  Summary

  YES, fully implemented with:
  1. ✅ UI configuration toggle
  2. ✅ Event-driven architecture
  3. ✅ API integration with Delivery API
  4. ✅ WhatsApp protocol read receipts (blue checkmarks)
  5. ✅ Respects user preference (can be disabled)
  6. ✅ Enabled by default (checkbox checked)

  The implementation is production-ready and follows Chatwoot's event-driven pattern consistently across all channels.
