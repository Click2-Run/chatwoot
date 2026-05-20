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

  describe '.default_url / .default_api_key (env resolution)' do
    it 'reads the canonical PROPRIACLOUD_API_URL env var when no DB row exists' do
      InstallationConfig.where(name: 'PROPRIACLOUD_API_URL').delete_all
      with_modified_env PROPRIACLOUD_API_URL: 'https://canonical.example.com/api/v1' do
        expect(described_class.default_url).to eq('https://canonical.example.com/api/v1')
      end
    end

    it 'reads the canonical PROPRIACLOUD_API_KEY env var when no DB row exists' do
      InstallationConfig.where(name: 'PROPRIACLOUD_API_KEY').delete_all
      with_modified_env PROPRIACLOUD_API_KEY: 'canonical-key' do
        expect(described_class.default_api_key).to eq('canonical-key')
      end
    end

    it 'still honors the legacy WHATSAPP_API_URL alias when only that is set' do
      InstallationConfig.where(name: 'PROPRIACLOUD_API_URL').delete_all
      with_modified_env WHATSAPP_API_URL: 'https://legacy.example.com/api/v1' do
        expect(described_class.default_url).to eq('https://legacy.example.com/api/v1')
      end
    end
  end

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
    let(:list_stub) do
      stub_request(:get, %r{#{Regexp.escape(provider_url)}/webhooks\?.*scope=instance})
        .to_return(status: 200, body: { data: { webhooks: [] } }.to_json)
    end

    it 'sends only the fields documented by CreateWebhookRequest (no `enabled`, no `active`)' do
      stub = stub_request(:post, "#{provider_url}/webhooks")
             .with do |req|
               body = JSON.parse(req.body)
               !body.key?('enabled') && !body.key?('active') && body['scope'] == 'instance'
             end
             .to_return(status: 201, body: { id: 'wh_inst_1' }.to_json)
      list_stub

      service.send(:register_webhook!)

      expect(stub).to have_been_requested
    end

    it 'treats 409 CONFLICT as idempotent success and still reconciles' do
      stub_request(:post, "#{provider_url}/webhooks")
        .to_return(status: 409, body: {
          success: false,
          error: { code: 'CONFLICT', message: 'webhook already exists for this instance scope target' }
        }.to_json)
      list_stub

      expect { service.send(:register_webhook!) }.not_to raise_error
      expect(list_stub).to have_been_requested
    end

    it 'does NOT emit a `whatsapp-api error: 409` ERROR log on the idempotent 409 path' do
      stub_request(:post, "#{provider_url}/webhooks")
        .to_return(status: 409, body: { error: { code: 'CONFLICT' } }.to_json)
      list_stub

      allow(Rails.logger).to receive(:error)
      service.send(:register_webhook!)
      expect(Rails.logger).not_to have_received(:error).with(/whatsapp-api error: 409/)
    end

    it 'raises ProviderUnavailableError when the POST genuinely fails (e.g. 500)' do
      stub_request(:post, "#{provider_url}/webhooks")
        .to_return(status: 500, body: { error: { code: 'INTERNAL' } }.to_json)

      expect { service.send(:register_webhook!) }
        .to raise_error(described_class::ProviderUnavailableError, /Failed to register webhook/)
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

    it 'raises PairRateLimitedError and stamps pair_locked_until on 429 PAIR_RATE_LIMITED' do
      stub_request(:post, "#{provider_url}/instances/pair/phonecode?instance_id=inst-123")
        .to_return(
          status: 429,
          body: {
            error: {
              code: 'PAIR_RATE_LIMITED',
              message: 'rate-overlimit',
              details: { recommended_cooldown_seconds: 300 }
            }
          }.to_json
        )

      expect { service.request_phone_pairing_code('5511999') }
        .to raise_error(described_class::PairRateLimitedError) do |err|
          expect(err.code).to eq('PAIR_RATE_LIMITED')
          expect(err.cooldown_seconds).to eq(300)
          expect(err.locked_until).to be_present
        end

      config = whatsapp_channel.reload.provider_config
      expect(config['pair_lock_code']).to eq('PAIR_RATE_LIMITED')
      expect(Time.zone.parse(config['pair_locked_until'])).to be_within(5.seconds).of(Time.current + 300)
    end
  end

  describe '#pair_qrcode (QR rate-limit parity)' do
    it 'raises PairRateLimitedError and stamps pair_locked_until on 429 PAIR_RATE_LIMITED' do
      stub_request(:get, "#{provider_url}/instances/pair/qrcode?instance_id=inst-123")
        .to_return(
          status: 429,
          body: {
            error: {
              code: 'PAIR_RATE_LIMITED',
              message: 'rate-overlimit',
              details: { recommended_cooldown_seconds: 300 }
            }
          }.to_json
        )

      expect { service.pair_qrcode }
        .to raise_error(described_class::PairRateLimitedError) do |err|
          expect(err.code).to eq('PAIR_RATE_LIMITED')
          expect(err.cooldown_seconds).to eq(300)
        end

      expect(whatsapp_channel.reload.provider_config['pair_locked_until']).to be_present
    end

    it 'raises ProviderUnavailableError on non-429 failures (no lock stamp)' do
      stub_request(:get, "#{provider_url}/instances/pair/qrcode?instance_id=inst-123")
        .to_return(status: 503, body: { error: { code: 'PROVIDER_DOWN' } }.to_json)

      expect { service.pair_qrcode }
        .to raise_error(described_class::ProviderUnavailableError, /Failed to fetch QR code.*503/)
      expect(whatsapp_channel.reload.provider_config['pair_locked_until']).to be_nil
    end
  end

  describe '#fetch_own_profile_picture_url (Imagem do Canal sync)' do
    it 'POSTs /contacts/profile-picture with the channel own JID and returns the url' do
      stub = stub_request(:post, "#{provider_url}/contacts/profile-picture?instance_id=inst-123")
             .with do |req|
               body = JSON.parse(req.body)
               body['jid']['user'].match?(/\A\d+\z/) &&
                 body['jid']['server'] == 's.whatsapp.net' &&
                 body['preview'] == false
             end
             .to_return(status: 200, body: { data: { url: 'https://wa.cdn/pic.jpg' } }.to_json)

      expect(service.fetch_own_profile_picture_url).to eq('https://wa.cdn/pic.jpg')
      expect(stub).to have_been_requested
    end

    it 'returns nil when the channel has no phone_number set' do
      whatsapp_channel.update_columns(phone_number: '')
      expect(service.fetch_own_profile_picture_url).to be_nil
    end

    it 'returns nil when the API returns no url' do
      stub_request(:post, "#{provider_url}/contacts/profile-picture?instance_id=inst-123")
        .to_return(status: 200, body: { data: { id: 'x' } }.to_json)
      expect(service.fetch_own_profile_picture_url).to be_nil
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

  describe 'WABA mode (connection_type=waba)' do
    let!(:waba_channel) do
      create(:channel_whatsapp,
             provider: 'propriacloud',
             provider_config: {
               provider_url: provider_url,
               api_key: api_key,
               instance_id: 'inst-waba-1',
               webhook_verify_token: 'b' * 32,
               connection_type: 'waba',
               phone_number_id: 'PNID-123',
               business_account_id: 'BAID-456'
             },
             validate_provider_config: false,
             received_messages: false,
             sync_templates: false)
    end
    let(:waba_service) { described_class.new(whatsapp_channel: waba_channel) }

    describe '#setup_channel_provider' do
      it 'sends waba:true with phone_number_id and business_account_id, and never pulls a QR' do
        create_stub = stub_request(:post, "#{provider_url}/instances/create")
                      .with do |req|
                        body = JSON.parse(req.body)
                        body['waba'] == true &&
                          body['phone_number_id'] == 'PNID-123' &&
                          body['business_account_id'] == 'BAID-456'
                      end
                      .to_return(status: 200, body: { data: {} }.to_json)
        stub_request(:post, "#{provider_url}/webhooks").to_return(status: 201, body: { data: {} }.to_json)
        stub_request(:get, %r{#{provider_url}/webhooks\?.*scope=instance}).to_return(status: 200, body: { data: { webhooks: [] } }.to_json)
        connect_stub = stub_request(:post, %r{#{provider_url}/instances/connect\?instance_id=inst-waba-1}).to_return(status: 200,
                                                                                                                     body: { data: {} }.to_json)
        qr_stub = stub_request(:get, %r{#{provider_url}/instances/pair/qrcode})

        waba_service.setup_channel_provider

        expect(create_stub).to have_been_requested
        expect(connect_stub).to have_been_requested
        expect(qr_stub).not_to have_been_requested
      end
    end

    describe '#pair_qrcode' do
      it 'raises ProviderUnavailableError without hitting the API' do
        qr_stub = stub_request(:get, %r{#{provider_url}/instances/pair/qrcode})
        expect { waba_service.pair_qrcode }
          .to raise_error(described_class::ProviderUnavailableError, /WABA-mode/i)
        expect(qr_stub).not_to have_been_requested
      end
    end

    describe '#request_phone_pairing_code' do
      it 'raises ProviderUnavailableError without hitting the API' do
        pc_stub = stub_request(:post, %r{#{provider_url}/instances/pair/phonecode})
        expect { waba_service.request_phone_pairing_code('+5511999') }
          .to raise_error(described_class::ProviderUnavailableError, /WABA-mode/i)
        expect(pc_stub).not_to have_been_requested
      end
    end

    describe '#validate_provider_config?' do
      it 'returns true when provider_url, api_key, phone_number_id and business_account_id are all present' do
        expect(waba_service.validate_provider_config?).to be(true)
      end

      it 'returns false when phone_number_id is missing' do
        waba_channel.provider_config['phone_number_id'] = ''
        expect(waba_service.validate_provider_config?).to be(false)
      end

      it 'returns false when business_account_id is missing' do
        waba_channel.provider_config['business_account_id'] = nil
        expect(waba_service.validate_provider_config?).to be(false)
      end
    end

    describe '#send_template' do
      it 'POSTs a Meta-shaped template body to /messages/send-template and returns the message_id' do
        stub = stub_request(:post, %r{#{provider_url}/messages/send-template\?instance_id=inst-waba-1})
               .with do |req|
                 body = JSON.parse(req.body)
                 body['type'] == 'template' &&
                   body['to'] == '5511999' &&
                   body.dig('template', 'name') == 'order_update' &&
                   body.dig('template', 'language', 'code') == 'en_US' &&
                   body.dig('template', 'components').is_a?(Array)
               end
               .to_return(status: 200, body: { data: { message_id: 'WAID-T-1' } }.to_json)

        result = waba_service.send_template(
          '5511999',
          { name: 'order_update', lang_code: 'en_US', parameters: [{ type: 'body', parameters: [] }] }
        )

        expect(stub).to have_been_requested
        expect(result).to eq('WAID-T-1')
      end
    end

    describe '#sync_templates' do
      it 'fetches /templates and stores the data array on the channel' do
        stub_request(:get, %r{#{provider_url}/templates\?instance_id=inst-waba-1})
          .to_return(status: 200, body: { data: { data: [{ name: 't1' }, { name: 't2' }] } }.to_json)

        waba_service.sync_templates
        waba_channel.reload

        expect(waba_channel.message_templates).to eq([{ 'name' => 't1' }, { 'name' => 't2' }])
        expect(waba_channel.message_templates_last_updated).to be_present
      end
    end
  end
end
