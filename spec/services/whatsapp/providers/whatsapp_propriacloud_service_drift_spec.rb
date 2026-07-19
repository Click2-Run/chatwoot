require 'rails_helper'

# Regression coverage for spec-drift fixes surfaced by the OpenAPI v1.4.0
# cross-reference audit: empty-JID presence/read receipts, the GET-only QR
# rebuild retry, WABA 428-on-delete, and the group topic/description split.
describe Whatsapp::Providers::WhatsappPropriacloudService do
  let(:provider_url) { 'https://propriacloud.example.com/api/v1' }
  let(:api_key) { 'pc-api-key-secret' }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp,
           provider: 'propriacloud',
           provider_config: {
             provider_url: provider_url, api_key: api_key,
             instance_id: 'inst-123', webhook_verify_token: 'a' * 32
           },
           validate_provider_config: false,
           received_messages: false)
  end
  let(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  describe '#toggle_typing_status (empty-JID regression)' do
    it 'targets the resolved recipient JID, not an empty user' do
      stub = stub_request(:post, "#{provider_url}/presence/chat?instance_id=inst-123")
             .with(body: hash_including('chat' => { 'user' => '5511999888', 'server' => 's.whatsapp.net' }))
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      service.toggle_typing_status(Events::Types::CONVERSATION_TYPING_ON, recipient_id: '5511999888')
      expect(stub).to have_been_requested
    end
  end

  describe '#read_messages (empty-JID regression)' do
    it 'marks read against the resolved recipient JID' do
      stub = stub_request(:post, "#{provider_url}/messages/mark-read?instance_id=inst-123")
             .with(body: hash_including('chat' => { 'user' => '5511999888', 'server' => 's.whatsapp.net' },
                                        'message_ids' => ['M1']))
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      msg = instance_double(Message, source_id: 'M1')
      service.read_messages([msg], recipient_id: '5511999888')
      expect(stub).to have_been_requested
    end
  end

  describe '#pair_qrcode 404 rebuild retry' do
    it 're-issues a GET (never a POST) against /instances/pair/qrcode' do
      # First QR GET → instance wiped upstream; rebuild; second QR GET → image.
      stub_request(:get, "#{provider_url}/instances/pair/qrcode?instance_id=inst-123")
        .to_return(
          { status: 404, body: { error: { code: 'NOT_FOUND' } }.to_json, headers: { 'Content-Type' => 'application/json' } },
          { status: 200, body: { success: true, data: { img: 'BASE64PNG' } }.to_json, headers: { 'Content-Type' => 'application/json' } }
        )
      # setup_channel_provider rebuild calls (create → webhooks → connect).
      stub_request(:post, %r{#{Regexp.escape(provider_url)}/instances/(create|connect)}).to_return(status: 200, body: { success: true }.to_json)
      stub_request(:post, "#{provider_url}/webhooks").to_return(status: 200, body: { success: true }.to_json)
      stub_request(:get, %r{#{Regexp.escape(provider_url)}/webhooks\?}).to_return(status: 200, body: { data: { webhooks: [] } }.to_json)

      service.pair_qrcode

      expect(a_request(:get, "#{provider_url}/instances/pair/qrcode?instance_id=inst-123")).to have_been_made.twice
      expect(a_request(:post, "#{provider_url}/instances/pair/qrcode?instance_id=inst-123")).not_to have_been_made
    end
  end

  describe '#disconnect_channel_provider WABA 428' do
    it 'unpairs then retries delete when the instance is still paired (428)' do
      stub_request(:post, "#{provider_url}/instances/delete?instance_id=inst-123")
        .to_return({ status: 428, body: { error: { code: 'PRECONDITION_REQUIRED' } }.to_json },
                   { status: 200, body: { success: true }.to_json })
      unpair = stub_request(:post, "#{provider_url}/instances/unpair?instance_id=inst-123")
               .to_return(status: 200, body: { success: true }.to_json)

      expect(service.disconnect_channel_provider).to be(true)
      expect(unpair).to have_been_requested
      expect(a_request(:post, "#{provider_url}/instances/delete?instance_id=inst-123")).to have_been_made.twice
    end
  end

  describe '#sync_group topic/description split' do
    let(:group_contact) do
      create(:contact, account: whatsapp_channel.inbox.account, group_type: :group,
                       identifier: '120363000000111@g.us',
                       additional_attributes: { 'description' => 'agent-authored description' })
    end
    let(:contact_inbox) { create(:contact_inbox, inbox: whatsapp_channel.inbox, contact: group_contact, source_id: '120363000000111') }
    let(:conversation) do
      create(:conversation, inbox: whatsapp_channel.inbox, contact: group_contact, contact_inbox: contact_inbox, group_type: :group)
    end

    it 'stores the API topic under `topic` and never clobbers a user-set `description`' do
      stub_request(:get, %r{#{Regexp.escape(provider_url)}/groups/info\?})
        .to_return(status: 200,
                   body: { success: true, data: { name: 'The Group', topic: 'quick tagline', participants: [] } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      service.sync_group(conversation, soft: true)

      group_contact.reload
      expect(group_contact.additional_attributes['topic']).to eq('quick tagline')
      expect(group_contact.additional_attributes['description']).to eq('agent-authored description')
    end
  end
end
