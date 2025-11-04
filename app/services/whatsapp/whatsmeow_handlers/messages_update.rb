# frozen_string_literal: true

# Whatsmeow Messages Update Handler
# Processes message status updates (sent, delivered, read) from Whatsmeow API
#
# Event payload format from Whatsmeow:
# {
#   event: "messages.update",
#   instance_id: "1234567890",
#   timestamp: 1699123456,
#   data: [
#     {
#       key: {
#         id: "message_id",
#         remote_jid: "1234567890@s.whatsapp.net",
#         from_me: true
#       },
#       update: {
#         status: "sent" | "delivered" | "read" | "failed",
#         timestamp: 1699123456
#       }
#     }
#   ]
# }

module Whatsapp::WhatsmeowHandlers::MessagesUpdate
  include Whatsapp::WhatsmeowHandlers::Helpers

  class MessageNotFoundError < StandardError; end

  private

  def process_messages_update
    updates = processed_params[:data] || []
    updates = [updates] unless updates.is_a?(Array)

    updates.each do |update|
      @message = nil
      @raw_message = update

      next handle_update if incoming?

      # Shared lock with Whatsapp::SendOnWhatsappService
      # Avoids race conditions when sending messages
      with_baileys_channel_lock_on_outgoing_message(inbox.channel.id) { handle_update }
    end
  end

  def handle_update
    raise MessageNotFoundError unless find_message_by_source_id(raw_message_id)

    update_status if status_from_update.present?
    handle_edited_content if edited_content_present?
  end

  def update_status
    status = status_mapper
    update_last_seen_at if incoming? && status == 'read'
    @message.update!(status: status) if status.present? && status_transition_allowed?(status)
  end

  def status_from_update
    @raw_message.dig(:update, :status) || @raw_message.dig(:update, 'status')
  end

  def status_mapper
    # Whatsmeow status values (simpler than Baileys):
    #  - "sent"      → (0) sent
    #  - "delivered" → (1) delivered
    #  - "read"      → (2) read
    #  - "failed"    → (3) failed
    #  - "pending"   → (0) sent
    status = status_from_update

    case status.to_s.downcase
    when 'sent', 'pending', 'server_ack'
      'sent'
    when 'delivered', 'delivery_ack'
      'delivered'
    when 'read'
      'read'
    when 'failed', 'error'
      'failed'
    else
      Rails.logger.warn "Whatsmeow unsupported message update status: #{status}"
      nil
    end
  end

  def update_last_seen_at
    conversation = @message.conversation
    to_update = { agent_last_seen_at: Time.current }
    to_update[:assignee_last_seen_at] = Time.current if conversation.assignee_id.present?

    conversation.update_columns(to_update) # rubocop:disable Rails/SkipsModelValidations
  end

  def status_transition_allowed?(new_status)
    return false if @message.status == 'read'
    return false if @message.status == 'delivered' && new_status == 'sent'

    true
  end

  def edited_content_present?
    @raw_message.dig(:update, :message).present? || @raw_message.dig(:update, 'message').present?
  end

  def handle_edited_content
    # Extract edited message content
    edited_msg = @raw_message.dig(:update, :message, :edited_message) ||
                 @raw_message.dig(:update, 'message', 'edited_message')
    return unless edited_msg

    @raw_message[:message] = edited_msg
    content = message_content

    return @message.update!(content: content, is_edited: true, previous_content: @message.content) if content

    Rails.logger.warn 'No valid message content found in the edit event'
  end
end
