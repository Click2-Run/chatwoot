# All Administrate controllers inherit from this
# `Administrate::ApplicationController`, making it the ideal place to put
# authentication logic or other before_actions.
#
# If you want to add pagination or other controller-level concerns,
# you're free to overwrite the RESTful controller actions.
class SuperAdmin::ApplicationController < Administrate::ApplicationController
  include ActionView::Helpers::TagHelper
  include ActionView::Context
  include SuperAdmin::NavigationHelper

  helper_method :render_vue_component, :settings_open?, :settings_pages
  # authenticiation done via devise : SuperAdmin Model
  before_action :authenticate_super_admin_or_redirect!

  # Override this value to specify the number of elements to display at a time
  # on index pages. Defaults to 20.
  # def records_per_page
  #   params[:per_page] || 20
  # end

  def order
    @order ||= Administrate::Order.new(
      params.fetch(resource_name, {}).fetch(:order, 'id'),
      params.fetch(resource_name, {}).fetch(:direction, 'desc')
    )
  end

  private

  def authenticate_super_admin_or_redirect!
    # Check if already authenticated as super_admin via Devise
    return if super_admin_signed_in?

    # Allow Super Admin access via existing user session if enabled
    # This is useful when using SSO/OpenID/OAuth providers where users don't have passwords
    if ENV.fetch('AUTH_SUPERADMIN_SAME_SESSION', 'false') == 'true'
      # Check if user is authenticated in regular session and is a SuperAdmin type
      if current_user&.is_a?(SuperAdmin)
        # Sign in the user as super_admin in the super_admin scope
        sign_in(:super_admin, current_user)
        return
      end
    end

    # Neither authenticated - redirect to super admin login
    redirect_to new_super_admin_session_path unless super_admin_signed_in?
  end

  def render_vue_component(component_name, props = {})
    html_options = {
      id: 'app',
      data: {
        component_name: component_name,
        props: props.to_json
      }
    }
    content_tag(:div, '', html_options)
  end

  def invalid_action_perfomed
    # rubocop:disable Rails/I18nLocaleTexts
    flash[:error] = 'Invalid action performed'
    # rubocop:enable Rails/I18nLocaleTexts
    redirect_back(fallback_location: root_path)
  end
end
