<!--
  @fileoverview Logto OAuth Login Button Component
  @module v3/components/LogtoOauth
  @category Authentication
  @description OAuth2/OpenID Connect login button that redirects users to Logto for authentication
  @architecture
    - Uses OmniAuth strategy configured in config/initializers/omniauth.rb
    - Redirects to /auth/logto which triggers the OAuth flow
    - Logto handles authentication and redirects back to /omniauth/logto/callback
    - DeviseOverrides::OmniauthCallbacksController processes the callback
  @dependencies
    - OmniAuth middleware
    - omniauth-openid-connect gem
    - Logto identity provider configuration (LOGTO_ENDPOINT, LOGTO_CLIENT_ID)
  @relatedFiles
    - config/initializers/omniauth.rb - OmniAuth Logto provider configuration
    - app/controllers/devise_overrides/omniauth_callbacks_controller.rb - Callback handler
    - app/javascript/v3/views/login/Index.vue - Login page that uses this button
  @example
    <LogtoOAuthButton />
  @created 2025-11-04
-->
<script>
export default {
  methods: {
    getLogtoAuthUrl() {
      // OmniAuth provides /auth/:provider routes automatically
      // This will initiate the OpenID Connect authorization flow
      return '/auth/logto';
    },
  },
};
</script>

<template>
  <div class="flex flex-col">
    <a
      :href="getLogtoAuthUrl()"
      class="inline-flex justify-center w-full px-4 py-3 bg-n-background dark:bg-n-solid-3 items-center rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
    >
      <span class="i-lucide-shield-check h-6 w-6 text-n-brand" />
      <span class="ml-2 text-base font-medium text-n-slate-12">
        {{ $t('LOGIN.OAUTH.LOGTO_LOGIN') }}
      </span>
    </a>
  </div>
</template>
