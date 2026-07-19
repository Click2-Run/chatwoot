require 'rails_helper'

# Inbound @g.us messages become group conversations (Contact + Conversation +
# GroupMember) via the shared GroupConversationHandler, reaching parity with
# the baileys provider. Gated by groups_enabled? at the routing layer.
describe Whatsapp::PropriacloudHandlers::GroupMessage do
  let(:webhook_verify_token) { 'a' * 32 }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp,
           provider: 'propriacloud',
           provider_config: { webhook_verify_token: webhook_verify_token, instance_id: 'inst-1' },
           validate_provider_config: false,
           received_messages: false)
  end
  let(:inbox) { whatsapp_channel.inbox }

  before do
    allow(Whatsapp::Providers::WhatsappPropriacloudService).to receive(:groups_enabled?).and_return(true)
    # Membership/metadata reconciliation is exercised in the provider spec;
    # here we only assert ingestion, so keep the async sync from hitting HTTP.
    allow(Contacts::SyncGroupJob).to receive(:perform_later)
  end

  def group_message(overrides = {})
    {
      'key' => {
        'id' => 'WA_GRP_1',
        'remote_jid' => '120363000000111@g.us',
        'participant' => '5511888777@s.whatsapp.net',
        'from_me' => false
      },
      'message' => { 'conversation' => 'hello group' },
      'push_name' => 'Alice',
      'message_timestamp' => 1_700_000_000
    }.merge(overrides)
  end

  def perform(messages)
    # Mirror production: the controller passes params.to_unsafe_hash and
    # ActiveJob restores it as HashWithIndifferentAccess, so the service
    # reads processed_params[:data] with symbol keys.
    params = {
      'webhook_verify_token' => webhook_verify_token,
      'event_type' => 'message.received',
      'instance_id' => 'inst-1',
      'data' => { 'messages' => messages }
    }.with_indifferent_access
    Whatsapp::IncomingMessagePropriacloudService.new(inbox: inbox, params: params).perform
  end

  it 'creates a group contact, conversation, member and message for an inbound group message' do
    perform([group_message])

    group_contact = inbox.account.contacts.find_by(identifier: '120363000000111@g.us')
    expect(group_contact).to be_present
    expect(group_contact.group_type_group?).to be(true)

    conversation = inbox.conversations.last
    expect(conversation.group_type_group?).to be(true)
    expect(conversation.messages.pluck(:content)).to include('hello group')

    sender = inbox.account.contacts.find_by(phone_number: '+5511888777')
    expect(sender).to be_present
    expect(GroupMember.where(group_contact: group_contact, contact: sender)).to exist
  end

  it 'attributes the message sender to the participant, not the group' do
    perform([group_message])

    message = inbox.conversations.last.messages.find_by(content: 'hello group')
    expect(message.message_type).to eq('incoming')
    expect(message.sender.phone_number).to eq('+5511888777')
  end

  it 'is idempotent on the WhatsApp message id' do
    perform([group_message])
    perform([group_message])

    expect(Message.where(source_id: 'WA_GRP_1').count).to eq(1)
  end

  it 'ignores group messages when the feature is disabled' do
    allow(Whatsapp::Providers::WhatsappPropriacloudService).to receive(:groups_enabled?).and_return(false)

    perform([group_message])

    expect(inbox.conversations.count).to eq(0)
  end
end
