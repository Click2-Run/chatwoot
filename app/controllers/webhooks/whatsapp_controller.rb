class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  def process_payload
    if inactive_whatsapp_number?
      Rails.logger.warn("Rejected webhook for inactive WhatsApp number: #{params[:phone_number]}")
      render json: { error: 'Inactive WhatsApp number' }, status: :unprocessable_entity
      return
    end

    perform_whatsapp_events_job
  end

  private

  def perform_whatsapp_events_job
    perform_sync if params[:awaitResponse].present?
    return if performed?

    Webhooks::WhatsappEventsJob.perform_later(job_params)
    head :ok
  end

  def perform_sync
    Webhooks::WhatsappEventsJob.perform_now(job_params)
  rescue Whatsapp::IncomingMessageBaileysService::InvalidWebhookVerifyToken
    head :unauthorized
  rescue Whatsapp::IncomingMessageBaileysService::MessageNotFoundError
    head :not_found
  end

  # Includes the request signature header and raw body so that providers
  # using HMAC-SHA256 (e.g. Própria Cloud whatsapp-api) can verify in the job.
  def job_params
    params.to_unsafe_hash.merge(
      _webhook_signature: request.headers['X-Webhook-Signature'],
      _webhook_raw_body: request.raw_post
    ).compact
  end

  def valid_token?(token)
    channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
    whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
    token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
  end

  def inactive_whatsapp_number?
    phone_number = params[:phone_number]
    return false if phone_number.blank?

    inactive_numbers = GlobalConfig.get_value('INACTIVE_WHATSAPP_NUMBERS').to_s
    return false if inactive_numbers.blank?

    inactive_numbers_array = inactive_numbers.split(',').map(&:strip)
    inactive_numbers_array.include?(phone_number)
  end
end
