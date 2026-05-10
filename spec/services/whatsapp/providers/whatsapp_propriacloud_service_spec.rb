require 'rails_helper'

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

  describe '#download_media (PEND-01 / PEND-02)' do
    let(:image_message) do
      {
        'url' => 'https://mmg.whatsapp.net/v/abc.enc',
        'directPath' => '/v/abc.enc',
        'mediaKey' => 'MK',
        'mimetype' => 'image/jpeg'
      }
    end
    let(:webhook_payload) do
      {
        'key' => { 'id' => 'WA_MSG_123', 'remote_jid' => '5511999@s.whatsapp.net', 'from_me' => false },
        'message' => { 'imageMessage' => image_message },
        'push_name' => 'Tester',
        'message_timestamp' => 1_700_000_000
      }
    end

    it 'unwraps `message.imageMessage` and POSTs the wrapped form expected by the API' do
      stub = stub_request(:post, "#{provider_url}/media/download?instance_id=inst-123")
             .with(body: { 'imageMessage' => image_message }.to_json)
             .to_return(
               status: 200,
               body: { success: true, data: { base64: Base64.strict_encode64('hello'), mime_type: 'image/jpeg' } }.to_json,
               headers: { 'Content-Type' => 'application/json' }
             )

      io = service.download_media(webhook_payload)

      expect(stub).to have_been_requested
      expect(io.read).to eq('hello')
    end

    it 'accepts snake_case `image_message` keys (legacy fazer-ai format) and remaps to camelCase' do
      legacy_payload = { 'key' => { 'id' => 'X' }, 'message' => { 'image_message' => image_message } }
      stub = stub_request(:post, "#{provider_url}/media/download?instance_id=inst-123")
             .with(body: { 'imageMessage' => image_message }.to_json)
             .to_return(status: 200, body: { data: { base64: Base64.strict_encode64('OK') } }.to_json)

      service.download_media(legacy_payload)

      expect(stub).to have_been_requested
    end

    it 'reads response field `base64` (PEND-02)' do
      stub_request(:post, "#{provider_url}/media/download?instance_id=inst-123")
        .to_return(status: 200, body: { data: { base64: Base64.strict_encode64('PNG_BYTES') } }.to_json)

      io = service.download_media(webhook_payload)
      expect(io.read).to eq('PNG_BYTES')
    end

    it 'raises Down::Error when the API rejects the payload' do
      stub_request(:post, "#{provider_url}/media/download?instance_id=inst-123")
        .to_return(status: 400, body: { error: 'unable to detect media type from payload' }.to_json)

      expect { service.download_media(webhook_payload) }.to raise_error(Down::Error)
    end

    it 'raises Down::Error when the response has no base64 field' do
      stub_request(:post, "#{provider_url}/media/download?instance_id=inst-123")
        .to_return(status: 200, body: { data: { mime_type: 'image/jpeg' } }.to_json)

      expect { service.download_media(webhook_payload) }.to raise_error(Down::Error, /missing base64/)
    end
  end

  describe '#on_whatsapp (PEND-04)' do
    it 'reads the canonical `is_on_whatsapp` field' do
      stub_request(:post, "#{provider_url}/contacts/onwhatsapp?instance_id=inst-123")
        .with(body: { phones: ['5511999'] }.to_json)
        .to_return(status: 200, body: [{ 'phone' => '5511999', 'is_on_whatsapp' => true, 'jid' => '5511999@s.whatsapp.net' }].to_json)

      result = service.on_whatsapp('5511999')
      expect(result['exists']).to be true
      expect(result['jid']).to eq('5511999@s.whatsapp.net')
    end

    it 'falls back to legacy `is_in` for older deployments' do
      stub_request(:post, "#{provider_url}/contacts/onwhatsapp?instance_id=inst-123")
        .to_return(status: 200, body: [{ 'is_in' => true, 'jid' => 'X' }].to_json)

      expect(service.on_whatsapp('5511')['exists']).to be true
    end

    it 'returns exists=false when the phone is not on WhatsApp' do
      stub_request(:post, "#{provider_url}/contacts/onwhatsapp?instance_id=inst-123")
        .to_return(status: 200, body: [{ 'is_on_whatsapp' => false }].to_json)

      expect(service.on_whatsapp('5511')['exists']).to be false
    end
  end

  describe '#register_webhook! (PEND-09)' do
    it 'does NOT send the undocumented `enabled` field' do
      stub = stub_request(:post, "#{provider_url}/webhooks")
             .with do |req|
               body = JSON.parse(req.body)
               !body.key?('enabled') && body['active'] == true && body['scope'] == 'instance'
             end
             .to_return(status: 201, body: { id: 'wh_inst_1' }.to_json)
      stub_request(:get, /#{Regexp.escape(provider_url)}\/webhooks\?scope=instance/).to_return(status: 200, body: { data: { webhooks: [] } }.to_json)

      service.send(:register_webhook!)

      expect(stub).to have_been_requested
    end
  end

  describe '#fetch_and_publish_qr_code (PEND-10)' do
    it 'renders the `img` data URL' do
      stub_request(:get, "#{provider_url}/instances/pair/qrcode?instance_id=inst-123")
        .to_return(status: 200, body: { data: { img: 'BASE64IMG' } }.to_json)

      service.fetch_and_publish_qr_code
      expect(whatsapp_channel.reload.provider_connection['qr_data_url']).to eq('data:image/png;base64,BASE64IMG')
    end

    it 'does NOT use plain-text `code` as a base64 image fallback' do
      stub_request(:get, "#{provider_url}/instances/pair/qrcode?instance_id=inst-123")
        .to_return(status: 200, body: { data: { code: '8charcode' } }.to_json)

      service.fetch_and_publish_qr_code
      expect(whatsapp_channel.reload.provider_connection['qr_data_url']).to be_nil
    end
  end

  describe '#request_phone_pairing_code (PEND-11)' do
    it 'defaults `expires_in` to 60 when the API does not return one' do
      stub_request(:post, "#{provider_url}/instances/pair/phonecode?instance_id=inst-123")
        .with(body: { phone: '5511999' }.to_json)
        .to_return(status: 200, body: { data: { code: 'AB12CD34', success: true } }.to_json)

      result = service.request_phone_pairing_code('+5511999')
      expect(result['code']).to eq('AB12CD34')
      expect(result['expires_in']).to eq(60)
    end

    it 'preserves an explicit `expires_in` when the API returns one' do
      stub_request(:post, "#{provider_url}/instances/pair/phonecode?instance_id=inst-123")
        .to_return(status: 200, body: { data: { code: 'X', expires_in: 30 } }.to_json)

      expect(service.request_phone_pairing_code('5511')['expires_in']).to eq(30)
    end
  end

  describe '#connect_only (Conectar action)' do
    it 'POSTs /instances/connect and flips provider_connection to `connecting`' do
      stub = stub_request(:post, "#{provider_url}/instances/connect?instance_id=inst-123")
             .to_return(status: 200, body: { data: { connection_state: 'connecting', pair_state: 'paired' } }.to_json)

      service.connect_only

      expect(stub).to have_been_requested
      whatsapp_channel.reload
      expect(whatsapp_channel.provider_connection['connection']).to eq('connecting')
      expect(whatsapp_channel.provider_connection['error']).to be_nil
    end

    it 'raises ProviderUnavailableError on non-2xx' do
      stub_request(:post, "#{provider_url}/instances/connect?instance_id=inst-123").to_return(status: 503, body: 'unavailable')
      expect { service.connect_only }.to raise_error(described_class::ProviderUnavailableError, /503/)
    end
  end

  describe '#request_chat_history (PEND-06)' do
    it 'POSTs to /sync/request-history with chat_jid and count' do
      stub = stub_request(:post, "#{provider_url}/sync/request-history")
             .with(body: { instance_id: 'inst-123', chat_jid: '5511999@s.whatsapp.net', count: 100 }.to_json)
             .to_return(status: 202, body: { data: { enqueued: true } }.to_json)

      result = service.request_chat_history(chat_jid: '5511999@s.whatsapp.net', count: 100)
      expect(stub).to have_been_requested
      expect(result['enqueued']).to be true
    end

    it 'raises ProviderUnavailableError on non-2xx' do
      stub_request(:post, "#{provider_url}/sync/request-history").to_return(status: 503, body: 'unavailable')
      expect { service.request_chat_history(chat_jid: 'x@s.whatsapp.net', count: 50) }
        .to raise_error(described_class::ProviderUnavailableError, /503/)
    end
  end

  describe '#send_media_message (PEND-16)' do
    let(:conversation) { create(:conversation, inbox: whatsapp_channel.inbox) }
    let(:msg) { create(:message, conversation: conversation, message_type: :outgoing, content: 'caption') }

    it 'sends up to 12 attachments per call with caption only on the first' do
      6.times do |i|
        msg.attachments.create!(
          account_id: msg.account_id,
          file_type: 'image',
          file: { io: StringIO.new("PNG_#{i}"), filename: "f#{i}.jpg", content_type: 'image/jpeg' }
        )
      end

      stub = stub_request(:post, "#{provider_url}/messages/send-media?instance_id=inst-123")
             .with do |req|
               body = JSON.parse(req.body)
               media = body['media']
               media.length == 6 &&
                 media[0]['caption'] == 'caption' &&
                 media[1..].all? { |item| !item.key?('caption') }
             end
             .to_return(status: 200, body: { data: { results: [{ message_id: 'WAID_1' }] } }.to_json)

      service.send(:instance_variable_set, :@message, msg)
      service.send(:instance_variable_set, :@phone_number, '5511999')
      result = service.send(:send_media_message)

      expect(stub).to have_been_requested
      expect(result).to eq('WAID_1')
    end
  end
end
