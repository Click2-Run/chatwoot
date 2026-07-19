require 'rails_helper'

# Group interface (create/participants/metadata/invite/settings) mapped onto
# the whatsapp-api /groups/* surface, plus group-aware JID routing on the
# outbound send path.
describe Whatsapp::Providers::WhatsappPropriacloudService do
  let(:provider_url) { 'https://propriacloud.example.com/api/v1' }
  let(:api_key) { 'pc-api-key-secret' }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp,
           provider: 'propriacloud',
           provider_config: {
             provider_url: provider_url,
             api_key: api_key,
             instance_id: 'inst-123',
             webhook_verify_token: 'a' * 32
           },
           validate_provider_config: false,
           received_messages: false)
  end
  let(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }
  let(:group_jid) { '120363000000111@g.us' }

  describe '#jid_param (server-aware)' do
    it 'normalizes phone JIDs to digits on s.whatsapp.net' do
      expect(service.send(:jid_param, '+55 11 99999-8888')).to eq(user: '5511999998888', server: 's.whatsapp.net')
    end

    it 'preserves the group id verbatim for @g.us JIDs' do
      expect(service.send(:jid_param, group_jid)).to eq(user: '120363000000111', server: 'g.us')
    end

    it 'strips the device suffix from a phone JID' do
      expect(service.send(:jid_param, '5511999:12@s.whatsapp.net')).to eq(user: '5511999', server: 's.whatsapp.net')
    end
  end

  describe '#create_group' do
    it 'POSTs name + JIDParam participants and surfaces the created group JID as :id' do
      stub = stub_request(:post, "#{provider_url}/groups/create?instance_id=inst-123")
             .with(body: { name: 'Team', participants: [{ user: '5511888', server: 's.whatsapp.net' }] }.to_json)
             .to_return(status: 200,
                        body: { success: true, data: { jid: { user: '120363000000111', server: 'g.us' }, name: 'Team' } }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      result = service.create_group('Team', ['5511888@s.whatsapp.net'])

      expect(stub).to have_been_requested
      expect(result[:id]).to eq('120363000000111@g.us')
    end
  end

  describe '#update_group_participants' do
    it 'POSTs the group JID, participants and action to /groups/participants' do
      stub = stub_request(:post, "#{provider_url}/groups/participants?instance_id=inst-123")
             .with(body: {
               group_jid: { user: '120363000000111', server: 'g.us' },
               participants: [{ user: '5511777', server: 's.whatsapp.net' }],
               action: 'add'
             }.to_json)
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.update_group_participants(group_jid, ['5511777@s.whatsapp.net'], 'add')).to be(true)
      expect(stub).to have_been_requested
    end
  end

  describe '#group_invite_code' do
    it 'returns the bare invite code (stripping the chat.whatsapp.com prefix)' do
      stub_request(:get, "#{provider_url}/groups/invite-link?instance_id=inst-123&jid=#{CGI.escape(group_jid)}&reset=false")
        .to_return(status: 200,
                   body: { success: true, data: { invite_link: 'https://chat.whatsapp.com/AbCdEf123' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(service.group_invite_code(group_jid)).to eq('AbCdEf123')
    end

    it 'rotates the link when revoking' do
      stub = stub_request(:get, "#{provider_url}/groups/invite-link?instance_id=inst-123&jid=#{CGI.escape(group_jid)}&reset=true")
             .to_return(status: 200,
                        body: { success: true, data: { invite_link: 'https://chat.whatsapp.com/NewCode99' } }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      expect(service.revoke_group_invite(group_jid)).to eq('NewCode99')
      expect(stub).to have_been_requested
    end
  end

  describe '#group_setting_update / mode toggles' do
    it 'maps announce -> PUT /groups/announce' do
      stub = stub_request(:put, "#{provider_url}/groups/announce?instance_id=inst-123")
             .with(body: { group_jid: { user: '120363000000111', server: 'g.us' }, announce: true }.to_json)
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.group_setting_update(group_jid, 'announce', true)).to be(true)
      expect(stub).to have_been_requested
    end

    it 'maps restrict -> PUT /groups/locked' do
      stub = stub_request(:put, "#{provider_url}/groups/locked?instance_id=inst-123")
             .with(body: { group_jid: { user: '120363000000111', server: 'g.us' }, locked: false }.to_json)
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.group_setting_update(group_jid, 'restrict', false)).to be(true)
      expect(stub).to have_been_requested
    end

    it 'maps join_approval_mode on -> enabled true' do
      stub = stub_request(:put, "#{provider_url}/groups/join-approval?instance_id=inst-123")
             .with(body: { group_jid: { user: '120363000000111', server: 'g.us' }, enabled: true }.to_json)
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.group_join_approval_mode(group_jid, 'on')).to be(true)
      expect(stub).to have_been_requested
    end

    it 'maps member_add_mode admin_add -> admins_only true' do
      stub = stub_request(:put, "#{provider_url}/groups/member-add-mode?instance_id=inst-123")
             .with(body: { group_jid: { user: '120363000000111', server: 'g.us' }, admins_only: true }.to_json)
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.group_member_add_mode(group_jid, 'admin_add')).to be(true)
      expect(stub).to have_been_requested
    end
  end

  describe '#group_leave' do
    it 'POSTs the group JID to /groups/leave' do
      stub = stub_request(:post, "#{provider_url}/groups/leave?instance_id=inst-123")
             .with(body: { group_jid: { user: '120363000000111', server: 'g.us' } }.to_json)
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.group_leave(group_jid)).to be(true)
      expect(stub).to have_been_requested
    end
  end

  describe '#allow_group_creation?' do
    it 'mirrors groups_enabled?' do
      allow(described_class).to receive(:groups_enabled?).and_return(true)
      expect(service.allow_group_creation?).to be(true)
      allow(described_class).to receive(:groups_enabled?).and_return(false)
      expect(service.allow_group_creation?).to be(false)
    end
  end

  describe 'outbound send routing to groups' do
    let(:conversation) { create(:conversation, inbox: whatsapp_channel.inbox) }
    let(:message) { create(:message, conversation: conversation, content: 'hi group', message_type: :outgoing) }

    it 'sends a text to a group recipient with server g.us' do
      stub = stub_request(:post, "#{provider_url}/messages/send?instance_id=inst-123")
             .with(body: hash_including('to' => { 'user' => '120363000000111', 'server' => 'g.us' }))
             .to_return(status: 200, body: { success: true, data: { message_id: 'WA1' } }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      service.send_message(group_jid, message)
      expect(stub).to have_been_requested
    end
  end
end
