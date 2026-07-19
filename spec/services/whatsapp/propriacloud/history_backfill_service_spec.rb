require 'rails_helper'

describe Whatsapp::Propriacloud::HistoryBackfillService do
  let(:provider_url) { 'https://propriacloud.example.com/api/v1' }
  let(:api_key) { 'pc-key' }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp,
           provider: 'propriacloud',
           provider_config: { provider_url: provider_url, api_key: api_key, instance_id: 'inst-1', webhook_verify_token: 'a' * 32 },
           validate_provider_config: false,
           received_messages: false)
  end
  let(:service) { described_class.new(channel: whatsapp_channel) }

  before do
    # Empty endpoints unless overridden per-test.
    stub_request(:get, %r{#{Regexp.escape(provider_url)}/labels}).to_return(status: 200, body: { data: { labels: [] } }.to_json)
    stub_request(:get, %r{#{Regexp.escape(provider_url)}/sync/push-names}).to_return(status: 200, body: { data: { push_names: [] } }.to_json)
    stub_request(:get, %r{#{Regexp.escape(provider_url)}/sync/contacts}).to_return(status: 200, body: { data: { contacts: [] } }.to_json)
    stub_request(:get, %r{#{Regexp.escape(provider_url)}/sync/conversations}).to_return(status: 200, body: { data: { conversations: [] } }.to_json)
  end

  describe 'PEND-12 — page cap and time cutoff' do
    let(:chat_jid) { '5511999@s.whatsapp.net' }
    let(:fresh_message) do
      {
        'key' => { 'id' => 'NEW1', 'remote_jid' => chat_jid, 'from_me' => false },
        'message' => { 'conversation' => 'hello' },
        'message_timestamp' => Time.current.to_i
      }
    end

    before do
      stub_request(:get, %r{#{Regexp.escape(provider_url)}/sync/conversations})
        .to_return(status: 200, body: { data: { conversations: [{ chat_jid: chat_jid }] } }.to_json)
    end

    it 'stops fetching messages after MAX_PAGES_PER_CHAT pages' do
      stub = stub_request(:get, %r{#{Regexp.escape(provider_url)}/sync/messages\?})
             .to_return(status: 200, body: { data: { messages: [fresh_message] } }.to_json)

      service.perform

      expect(stub).to have_been_requested.times(described_class::MAX_PAGES_PER_CHAT)
    end

    it 'stops once messages older than the cutoff are encountered' do
      whatsapp_channel.provider_config['history_backfill_max_age_days'] = 30
      whatsapp_channel.save!
      service_with_cutoff = described_class.new(channel: whatsapp_channel.reload)

      old_message = fresh_message.merge('message_timestamp' => 90.days.ago.to_i, 'key' => fresh_message['key'].merge('id' => 'OLD1'))
      page1 = stub_request(:get, %r{#{Regexp.escape(provider_url)}/sync/messages\?.*page=1})
              .to_return(status: 200, body: { data: { messages: [fresh_message, old_message] } }.to_json)
      page2 = stub_request(:get, %r{#{Regexp.escape(provider_url)}/sync/messages\?.*page=2})
              .to_return(status: 200, body: { data: { messages: [fresh_message] } }.to_json)

      service_with_cutoff.perform

      expect(page1).to have_been_requested
      expect(page2).not_to have_been_requested
    end
  end

  describe 'PEND-13 — push-names backfill' do
    it 'walks /sync/push-names and stores names for the contact pass' do
      stub = stub_request(:get, %r{#{Regexp.escape(provider_url)}/sync/push-names})
             .to_return(status: 200, body: { data: { push_names: [{ jid: '5511999@s.whatsapp.net', push_name: 'John Doe' }] } }.to_json)
      stub_request(:get, %r{#{Regexp.escape(provider_url)}/sync/contacts})
        .to_return(status: 200, body: { data: { contacts: [{ jid: '5511999@s.whatsapp.net' }] } }.to_json)

      service.perform

      expect(stub).to have_been_requested
      contact = Contact.find_by(account: whatsapp_channel.inbox.account)
      expect(contact&.name).to eq('John Doe')
    end
  end

  describe 'contact phone resolution (LID mis-keying regression)' do
    it 'uses phone_number / pn_jid and skips lid_mapping rows that carry only a LID' do
      stub_request(:get, %r{#{Regexp.escape(provider_url)}/sync/contacts})
        .to_return(
          { status: 200, body: { data: { contacts: [
            { jid: '5511999@s.whatsapp.net', full_name: 'Real Phone' },
            { jid: '5511888@s.whatsapp.net', pn_jid: '5511888@s.whatsapp.net', full_name: 'Via Pn' },
            { jid: '999888777@lid', source: 'lid_mapping', full_name: 'LID Only' }
          ] } }.to_json },
          { status: 200, body: { data: { contacts: [] } }.to_json }
        )

      service.perform

      account = whatsapp_channel.inbox.account
      expect(account.contacts.find_by(phone_number: '+5511999')).to be_present
      expect(account.contacts.find_by(phone_number: '+5511888')).to be_present
      # The pure-LID row must NOT mint a fabricated "+<lid>" contact.
      expect(account.contacts.where(phone_number: '+999888777')).to be_empty
      expect(account.contacts.where("name = 'LID Only'")).to be_empty
    end
  end

  describe 'PEND-05 — idempotency / force flag' do
    it 'stamps history_backfill_completed_at' do
      service.perform
      expect(whatsapp_channel.reload.provider_config['history_backfill_completed_at']).to be_present
    end
  end
end
