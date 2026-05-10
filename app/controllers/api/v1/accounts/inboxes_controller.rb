class Api::V1::Accounts::InboxesController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  include Api::V1::InboxesHelper
  before_action :fetch_inbox, except: [:index, :create]
  before_action :fetch_agent_bot, only: [:set_agent_bot]
  before_action :validate_limit, only: [:create]
  # we are already handling the authorization in fetch inbox
  # rubocop:disable Rails/LexicallyScopedActionFilter -- health is defined in WhatsappHealthManagement concern
  before_action :check_authorization, except: [:show, :health, :setup_channel_provider, :refresh_provider_status]
  before_action :validate_whatsapp_cloud_channel, only: [:health]
  # rubocop:enable Rails/LexicallyScopedActionFilter
  include Api::V1::Accounts::Concerns::WhatsappHealthManagement

  def index
    @inboxes = policy_scope(Current.account.inboxes.order_by_name.includes(:channel, { avatar_attachment: [:blob] }))
  end

  def show; end

  # Deprecated: This API will be removed in 2.7.0
  def assignable_agents
    @assignable_agents = @inbox.assignable_agents
  end

  def campaigns
    @campaigns = @inbox.campaigns
  end

  def avatar
    @inbox.avatar.attachment.destroy! if @inbox.avatar.attached?
    head :ok
  end

  def create
    ActiveRecord::Base.transaction do
      channel = create_channel
      @inbox = Current.account.inboxes.build(
        {
          name: inbox_name(channel),
          channel: channel
        }.merge(
          permitted_params.except(:channel)
        )
      )
      @inbox.save!
    end
  end

  def update
    inbox_params = permitted_params.except(:channel, :csat_config)
    inbox_params[:csat_config] = format_csat_config(permitted_params[:csat_config]) if permitted_params[:csat_config].present?
    @inbox.update!(inbox_params)
    update_inbox_working_hours
    update_channel if channel_update_required?
  end

  def agent_bot
    @agent_bot = @inbox.agent_bot
  end

  def set_agent_bot
    if @agent_bot
      agent_bot_inbox = @inbox.agent_bot_inbox || AgentBotInbox.new(inbox: @inbox)
      agent_bot_inbox.agent_bot = @agent_bot
      agent_bot_inbox.save!
    elsif @inbox.agent_bot_inbox.present?
      @inbox.agent_bot_inbox.destroy!
    end
    head :ok
  end

  def reset_secret
    return head :not_found unless @inbox.api?

    @inbox.channel.reset_secret!
  end

  def setup_channel_provider
    channel = @inbox.channel

    unless channel.respond_to?(:setup_channel_provider)
      render json: { error: 'Channel does not support setup' }, status: :unprocessable_entity and return
    end

    fetch_qr_param = params.key?(:fetch_qr) ? ActiveModel::Type::Boolean.new.cast(params[:fetch_qr]) : true
    if channel.provider_service.method(:setup_channel_provider).parameters.any? { |kind, name| kind == :key && name == :fetch_qr }
      channel.provider_service.setup_channel_provider(fetch_qr: fetch_qr_param)
    else
      channel.setup_channel_provider
    end
    head :ok
  end

  def disconnect_channel_provider
    channel = @inbox.channel

    unless channel.respond_to?(:disconnect_channel_provider)
      render json: { error: 'Channel does not support disconnect' }, status: :unprocessable_entity and return
    end

    channel.disconnect_channel_provider
    head :ok
  ensure
    channel.update_provider_connection!(connection: 'close') if channel.respond_to?(:update_provider_connection!)
  end

  def pair_phone_code
    channel = @inbox.channel
    phone = params[:phone].presence || channel.phone_number

    unless channel.provider_service.respond_to?(:request_phone_pairing_code)
      render json: { error: 'Channel does not support phone-code pairing' }, status: :unprocessable_entity and return
    end

    result = channel.provider_service.request_phone_pairing_code(phone)
    render json: result
  rescue StandardError => e
    render json: friendly_pair_error(e), status: :unprocessable_entity
  end

  # Reconciles the cached provider_connection on the channel with the
  # truth from the upstream API (e.g. propriacloud's /instances/status).
  # Used by the dashboard on inbox open to clear stale "connecting"
  # state left over from abandoned pairing attempts. Rate-limited via
  # Redis so a chatty UI cannot flood the upstream API.
  def refresh_provider_status
    # Read-only state reconciliation — anyone who can show? the inbox
    # may trigger it. Rate-limited via Redis below to 1/30s/channel.
    authorize @inbox, :show?

    channel = @inbox.channel
    unless channel.provider_service.respond_to?(:reconcile!) ||
           channel.provider_service.respond_to?(:refresh_status_from_api!)
      render json: { error: 'Channel does not support status refresh' }, status: :unprocessable_entity and return
    end

    # Two-tier rate limit:
    #  - "soft" 5s window: still calls refresh_status_from_api! (cheap GET
    #    /instances/status, ~50ms). Cap concurrent UI navigation from
    #    spamming the upstream while still keeping the cached state honest.
    #  - "hard" 60s window: skip the heavier reconcile! path (which also
    #    re-registers webhook + enqueues backfill). Webhook re-registration
    #    is expensive and only needs to run periodically.
    soft_key = "propriacloud:soft_refresh:#{channel.id}"
    hard_key = "propriacloud:hard_refresh:#{channel.id}"
    soft_blocked = Redis::Alfred.get(soft_key)
    hard_blocked = Redis::Alfred.get(hard_key)

    unless soft_blocked
      Redis::Alfred.setex(soft_key, true, 5)
      if !hard_blocked && channel.provider_service.respond_to?(:reconcile!)
        Redis::Alfred.setex(hard_key, true, 60)
        channel.provider_service.reconcile!
      else
        channel.provider_service.refresh_status_from_api!
      end
    end

    render json: {
      rate_limited: !!soft_blocked,
      provider_connection: channel.reload.provider_connection
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def convert_provider
    channel = @inbox.channel

    unless channel.respond_to?(:convert_provider!)
      render json: { error: 'Channel does not support provider conversion' }, status: :unprocessable_entity and return
    end

    new_provider = params.require(:provider)
    new_provider_config = (params.permit(provider_config: {})[:provider_config] || {}).to_h

    channel.convert_provider!(new_provider: new_provider, new_provider_config: new_provider_config)
    render :show
  rescue ActionController::ParameterMissing => e
    render json: { message: e.message }, status: :bad_request
  rescue ActiveRecord::RecordInvalid => e
    render json: { message: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Provider conversion failed for inbox #{@inbox.id}: #{e.class}: #{e.message}"
    render json: { message: 'Provider conversion failed. Please check your credentials and the previous provider session, then try again.' },
           status: :unprocessable_entity
  end

  def destroy
    ::DeleteObjectJob.perform_later(@inbox, Current.user, request.ip) if @inbox.present?
    render status: :ok, json: { message: I18n.t('messages.inbox_deletetion_response') }
  end

  def on_whatsapp
    params.require(:phone_number)
    phone_number = params[:phone_number]
    channel = @inbox.channel

    unless channel.respond_to?(:on_whatsapp)
      render json: { error: 'Channel does not support whatsapp check' }, status: :unprocessable_entity and return
    end

    response = channel.on_whatsapp(phone_number)

    render json: response, status: :ok
  end

  # Translate provider raw errors (especially WhatsApp rate-limit /
  # device-limit responses) into a compact, locale-friendly shape the
  # dashboard can show without leaking server internals (proxy IPs,
  # raw IQ XML, file paths). Keeps the original message available
  # under `details` for support tooling but strips it from the user
  # surface.
  def friendly_pair_error(exception)
    raw = exception.message.to_s
    code = nil
    user_message = nil
    cooldown = nil

    if raw.include?('PAIR_RATE_LIMITED') || raw.match?(/429.*rate-overlimit|rate-?overlimit/i)
      code = 'PAIR_RATE_LIMITED'
      user_message = 'WhatsApp temporarily blocked new pair attempts. ' \
                     'Wait at least 5 minutes before trying again.'
      cooldown = 300
    elsif raw.match?(/PAIR_DEVICE_LIMIT|too many.*linked|maximum.*devices/i)
      code = 'PAIR_DEVICE_LIMIT'
      user_message = 'WhatsApp limit of linked devices reached. ' \
                     'Open WhatsApp → Settings → Linked devices and remove an old one, then retry.'
    elsif raw.match?(/expired|invalid.*code/i)
      code = 'PAIR_CODE_EXPIRED'
      user_message = 'The pairing code expired. Click Emparelhar again to generate a fresh one.'
    else
      code = 'PAIR_FAILED'
      user_message = 'Could not request a pairing code. Please try again in a moment.'
    end

    { error: user_message, code: code, cooldown_seconds: cooldown }.compact
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:id])
    authorize @inbox, :show?
  end

  def fetch_agent_bot
    @agent_bot = AgentBot.find(params[:agent_bot]) if params[:agent_bot]
  end

  def create_channel
    return unless allowed_channel_types.include?(permitted_params[:channel][:type])

    account_channels_method.create!(permitted_params(channel_type_from_params::EDITABLE_ATTRS)[:channel].except(:type))
  end

  def allowed_channel_types
    %w[web_widget api email line telegram whatsapp sms]
  end

  def update_inbox_working_hours
    @inbox.update_working_hours(params.permit(working_hours: Inbox::OFFISABLE_ATTRS)[:working_hours]) if params[:working_hours]
  end

  def update_channel
    channel_attributes = get_channel_attributes(@inbox.channel_type)
    return if permitted_params(channel_attributes)[:channel].blank?

    validate_and_update_email_channel(channel_attributes) if @inbox.inbox_type == 'Email'

    reauthorize_and_update_channel(channel_attributes)
    update_channel_feature_flags
  end

  def channel_update_required?
    permitted_params(get_channel_attributes(@inbox.channel_type))[:channel].present?
  end

  def validate_and_update_email_channel(channel_attributes)
    validate_email_channel(channel_attributes)
  rescue StandardError => e
    render json: { message: e }, status: :unprocessable_entity and return
  end

  def reauthorize_and_update_channel(channel_attributes)
    @inbox.channel.reauthorized! if @inbox.channel.respond_to?(:reauthorized!)
    @inbox.channel.update!(permitted_params(channel_attributes)[:channel])
  end

  def update_channel_feature_flags
    return unless @inbox.web_widget?
    return unless permitted_params(Channel::WebWidget::EDITABLE_ATTRS)[:channel].key? :selected_feature_flags

    @inbox.channel.selected_feature_flags = permitted_params(Channel::WebWidget::EDITABLE_ATTRS)[:channel][:selected_feature_flags]
    @inbox.channel.save!
  end

  def format_csat_config(config)
    formatted = {
      'display_type' => config['display_type'] || 'emoji',
      'message' => config['message'] || '',
      :survey_rules => {
        'operator' => config.dig('survey_rules', 'operator') || 'contains',
        'values' => config.dig('survey_rules', 'values') || []
      },
      'button_text' => config['button_text'] || 'Please rate us',
      'language' => config['language'] || 'en'
    }
    format_template_config(config, formatted)
    formatted
  end

  def format_template_config(config, formatted)
    formatted['template'] = config['template'] if config['template'].present?
  end

  def inbox_attributes
    [:name, :avatar, :greeting_enabled, :greeting_message, :enable_email_collect, :csat_survey_enabled,
     :enable_auto_assignment, :working_hours_enabled, :out_of_office_message, :timezone, :allow_messages_after_resolved,
     :lock_to_single_conversation, :portal_id, :sender_name_type, :business_name,
     { csat_config: [:display_type, :message, :button_text, :language,
                     { survey_rules: [:operator, { values: [] }],
                       template: [:name, :template_id, :friendly_name, :content_sid, :approval_sid,
                                  :created_at, :linked_at, :language, :source, :status, { body_variables: {} }] }] }]
  end

  def permitted_params(channel_attributes = [])
    # We will remove this line after fixing https://linear.app/chatwoot/issue/CW-1567/null-value-passed-as-null-string-to-backend
    params.each { |k, v| params[k] = params[k] == 'null' ? nil : v }
    params.permit(*inbox_attributes, channel: [:type, *channel_attributes])
  end

  def channel_type_from_params
    {
      'web_widget' => Channel::WebWidget,
      'api' => Channel::Api,
      'email' => Channel::Email,
      'line' => Channel::Line,
      'telegram' => Channel::Telegram,
      'whatsapp' => Channel::Whatsapp,
      'sms' => Channel::Sms
    }[permitted_params[:channel][:type]]
  end

  def get_channel_attributes(channel_type)
    channel_type.constantize.const_defined?(:EDITABLE_ATTRS) ? channel_type.constantize::EDITABLE_ATTRS.presence : []
  end
end

Api::V1::Accounts::InboxesController.prepend_mod_with('Api::V1::Accounts::InboxesController')
