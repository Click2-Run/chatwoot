<!--
  @fileoverview Click2Run OpenID Connect Login Button Component
  @module v3/components/Click2RunOpenid
  @category Authentication
  @description OAuth2/OpenID Connect login button that redirects users to Click2Run Auth for authentication
  @architecture
    - Uses OmniAuth strategy configured in config/initializers/omniauth.rb
    - Redirects to /auth/click2run which triggers the OAuth flow
    - Click2Run Auth handles authentication and redirects back to /omniauth/click2run/callback
    - DeviseOverrides::OmniauthCallbacksController processes the callback
  @dependencies
    - OmniAuth middleware
    - omniauth-openid-connect gem
    - Click2Run OpenID provider configuration (CLICK2RUN_OPENID_ISSUER, CLICK2RUN_OPENID_APP_ID)
  @relatedFiles
    - config/initializers/omniauth.rb - OmniAuth Click2Run provider configuration
    - app/controllers/devise_overrides/omniauth_callbacks_controller.rb - Callback handler
    - app/javascript/v3/views/login/Index.vue - Login page that uses this button
  @example
    <Click2RunOpenidButton />
  @created 2025-11-04
-->
<script>
export default {
  methods: {
    getClick2RunAuthUrl() {
      // OmniAuth provides /auth/:provider routes automatically
      // This will initiate the OpenID Connect authorization flow
      return '/auth/click2run';
    },
  },
};
</script>

<template>
  <div class="flex flex-col">
    <a
      :href="getClick2RunAuthUrl()"
      class="inline-flex justify-center w-full px-4 py-3 bg-n-background dark:bg-n-solid-3 items-center rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
    >
      <span class="i-lucide-shield-check h-6 w-6 text-n-brand" />
      <span class="ml-2 text-base font-medium text-n-slate-12">
        {{ $t('LOGIN.OAUTH.CLICK2RUN_LOGIN') }}
      </span>
    </a>
  </div>
</template>
