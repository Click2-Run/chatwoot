<!--
  @fileoverview Própria Cloud OpenID Connect Login Button Component
  @module v3/components/PropriacloudOpenid
  @category Authentication
  @description OAuth2/OpenID Connect login button that redirects users to Própria Cloud Auth for authentication
  @architecture
    - Uses OmniAuth strategy configured in config/initializers/omniauth.rb
    - Redirects to /auth/propriacloud which triggers the OAuth flow
    - Própria Cloud Auth handles authentication and redirects back to /omniauth/propriacloud/callback
    - DeviseOverrides::OmniauthCallbacksController processes the callback
    - Button label is dynamically configured via PROPRIACLOUD_OPENID_LABEL environment variable
  @dependencies
    - OmniAuth middleware
    - omniauth-openid-connect gem
    - Própria Cloud OpenID provider configuration (PROPRIACLOUD_OPENID_ISSUER, PROPRIACLOUD_OPENID_APP_ID, PROPRIACLOUD_OPENID_LABEL)
  @relatedFiles
    - config/initializers/omniauth.rb - OmniAuth Própria Cloud provider configuration
    - app/controllers/devise_overrides/omniauth_callbacks_controller.rb - Callback handler
    - app/javascript/v3/views/login/Index.vue - Login page that uses this button
    - app/views/layouts/vueapp.html.erb - Passes PROPRIACLOUD_OPENID_LABEL to frontend
  @example
    <PropriacloudOpenidButton />
  @created 2025-11-04
-->
<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const getPropriacloudAuthUrl = () => {
  // OmniAuth provides /auth/:provider routes automatically
  // This will initiate the OpenID Connect authorization flow
  return '/auth/propriacloud';
};

// Use dynamic label from config or fall back to i18n translation
const buttonLabel = computed(() => {
  const configuredLabel = window.chatwootConfig?.propriacloudOpenidLabel;
  return configuredLabel || t('LOGIN.OAUTH.PROPRIACLOUD_LOGIN');
});
</script>

<template>
  <div class="flex flex-col">
    <a
      :href="getPropriacloudAuthUrl()"
      class="inline-flex justify-center w-full px-4 py-3 bg-n-background dark:bg-n-solid-3 items-center rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
    >
      <span class="i-lucide-shield-check h-6 w-6 text-n-brand" />
      <span class="ml-2 text-base font-medium text-n-slate-12">
        {{ buttonLabel }}
      </span>
    </a>
  </div>
</template>
