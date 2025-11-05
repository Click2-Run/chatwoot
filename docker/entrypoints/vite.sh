#!/bin/sh
set -x

# Only remove PID files, preserve cache directories
rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/bootsnap/compile-cache-iseq 2>/dev/null || true
rm -rf /app/tmp/cache/bootsnap/compile-cache-yaml 2>/dev/null || true

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
# Don't prune store - preserve cached packages
# Use cached installations instead of --force
pnpm install

echo "Ready to run Vite development server."

exec "$@"
