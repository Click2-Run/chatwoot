require 'rails_helper'

describe Whatsapp::PropriacloudHandlers::Helpers, type: :model do
  let!(:channel_a) { create(:channel_whatsapp, provider: 'propriacloud', validate_provider_config: false, received_messages: false) }
  let!(:channel_b) do
    create(:channel_whatsapp,
           provider: 'propriacloud',
           phone_number: '+5511888777666',
           validate_provider_config: false,
           received_messages: false)
  end

  let(:helper_class) do
    Class.new do
      include Whatsapp::PropriacloudHandlers::Helpers

      attr_accessor :inbox, :raw_message

      def initialize(inbox)
        @inbox = inbox
      end
    end
  end

  describe 'PEND-07 — Redis lock key is inbox-scoped' do
    it 'produces distinct keys for the same WA message id across two inboxes' do
      shared_wa_id = 'SAME_WA_ID_123'

      h_a = helper_class.new(channel_a.inbox)
      h_a.raw_message = { key: { id: shared_wa_id } }
      h_b = helper_class.new(channel_b.inbox)
      h_b.raw_message = { key: { id: shared_wa_id } }

      key_a = h_a.send(:message_processing_lock_key)
      key_b = h_b.send(:message_processing_lock_key)

      expect(key_a).to include(channel_a.inbox.id.to_s)
      expect(key_b).to include(channel_b.inbox.id.to_s)
      expect(key_a).not_to eq(key_b)
    end
  end
end
