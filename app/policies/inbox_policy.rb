class InboxPolicy < ApplicationPolicy
  class Scope
    attr_reader :user_context, :user, :scope, :account, :account_user

    def initialize(user_context, scope)
      @user_context = user_context
      @user = user_context[:user]
      @account = user_context[:account]
      @account_user = user_context[:account_user]
      @scope = scope
    end

    def resolve
      user.assigned_inboxes
    end
  end

  def index?
    true
  end

  def show?
    # FIXME: for agent bots, lets bring this validation to policies as well in future
    return true if @user.is_a?(AgentBot)

    Current.user.assigned_inboxes.include? record
  end

  def assignable_agents?
    true
  end

  def agent_bot?
    true
  end

  def campaigns?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def set_agent_bot?
    @account_user.administrator?
  end

  def avatar?
    @account_user.administrator?
  end

  def sync_templates?
    @account_user.administrator?
  end

  def health?
    @account_user.administrator?
  end

  def reset_secret?
    @account_user.administrator?
  end

  def disconnect_channel_provider?
    @account_user.administrator?
  end

  def pair_qrcode?
    @account_user.administrator?
  end

  def pair_phone_code?
    @account_user.administrator?
  end

  def connect_only?
    @account_user.administrator?
  end

  def disconnect_only?
    @account_user.administrator?
  end

  def unpair_only?
    @account_user.administrator?
  end

  def refresh_provider_status?
    # Read-only refresh; available to anyone allowed to view the inbox.
    show?
  end

  def audit_stream?
    # SSE subscription is read-only; anyone allowed to view the inbox
    # can subscribe so agents see live pair/connection state changes
    # while working in the conversation view.
    show?
  end

  def resync_history?
    @account_user.administrator?
  end

  def request_chat_history?
    @account_user.administrator?
  end

  def sync_avatar_from_provider?
    @account_user.administrator?
  end

  def convert_provider?
    @account_user.administrator?
  end

  def on_whatsapp?
    true
  end

  def enable_whatsapp_calling?
    @account_user.administrator?
  end

  def disable_whatsapp_calling?
    @account_user.administrator?
  end

  def set_inbound_calls?
    @account_user.administrator?
  end
end
