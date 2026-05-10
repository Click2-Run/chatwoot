require 'rails_helper'

describe Whatsapp::PropriacloudHandlers::Appstate do
  let(:webhook_verify_token) { 'a' * 32 }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp,
           provider: 'propriacloud',
           provider_config: { webhook_verify_token: webhook_verify_token, instance_id: 'inst-1' },
           validate_provider_config: false,
           received_messages: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:contact_inbox) do
    create(:contact_inbox, inbox: inbox, source_id: '5511999',
                           contact: create(:contact, account: inbox.account))
  end
  let!(:conversation) { create(:conversation, inbox: inbox, contact_inbox: contact_inbox, status: :open) }

  def perform(event:, data:, timestamp: nil)
    params = {
      'webhook_verify_token' => webhook_verify_token,
      'event_type' => event,
      'instance_id' => 'inst-1',
      'data' => data
    }
    params['timestamp'] = timestamp if timestamp
    Whatsapp::IncomingMessagePropriacloudService.new(inbox: inbox, params: params).perform
  end

  describe 'PEND-08 — out-of-order webhook timestamp guard' do
    it 'drops an `appstate.archive` event whose timestamp predates conversation.updated_at' do
      conversation.update!(status: :open, updated_at: 1.hour.ago)
      stale_ts = (conversation.updated_at - 10.minutes).to_i

      perform(event: 'appstate.archive',
              data: { 'chat_jid' => '5511999@s.whatsapp.net', 'archived' => true, 'timestamp' => stale_ts })

      expect(conversation.reload.status).to eq('open')
    end

    it 'applies a fresh `appstate.archive` event' do
      conversation.update!(status: :open, updated_at: 1.hour.ago)
      fresh_ts = Time.current.to_i

      perform(event: 'appstate.archive',
              data: { 'chat_jid' => '5511999@s.whatsapp.net', 'archived' => true, 'timestamp' => fresh_ts })

      expect(conversation.reload.status).to eq('resolved')
    end

    it 'tolerates events without a timestamp (applies them)' do
      conversation.update!(status: :open)
      perform(event: 'appstate.archive', data: { 'chat_jid' => '5511999@s.whatsapp.net', 'archived' => true })

      expect(conversation.reload.status).to eq('resolved')
    end
  end
end
