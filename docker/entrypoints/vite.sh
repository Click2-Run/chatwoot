#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

# Install gems first (required for bin/vite which is called by husky during pnpm install)
# Configure git to avoid hardlink errors in shared Docker volumes
echo "Installing bundle gems..."
export GIT_CLONE_PROTECTION_ACTIVE=false
git config --global core.cloneUseHardlinks false

# Force bundle to reinstall git-based gems without hardlinks
bundle config set --local force_ruby_platform true
bundle install || {
  echo "First bundle install failed, cleaning and retrying..."
  rm -rf /gems/ruby/3.4.0/bundler/gems/devise-secure_password-*
  rm -rf /gems/ruby/3.4.0/cache/bundler/git/devise-secure_password-*
  bundle install
}

echo "Installing pnpm dependencies..."
pnpm store prune
pnpm install --force

echo "Ready to run Vite development server."

exec "$@"
