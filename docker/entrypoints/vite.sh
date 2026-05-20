#!/bin/sh
set -x

# Only remove PID files, preserve cache directories
rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/bootsnap/compile-cache-iseq 2>/dev/null || true
rm -rf /app/tmp/cache/bootsnap/compile-cache-yaml 2>/dev/null || true

# Configure git to avoid hardlink errors in shared Docker volumes
export GIT_CLONE_PROTECTION_ACTIVE=false
git config --global core.cloneUseHardlinks false

# Quick check if gems need updating (much faster than full bundle install)
# Only install if Gemfile.lock changed or gems are missing
if ! bundle check > /dev/null 2>&1; then
  echo "Gems need updating, running bundle install..."
  bundle config set --local force_ruby_platform true
  bundle install || {
    echo "Bundle install failed, cleaning git-based gems and retrying..."
    rm -rf /gems/ruby/3.4.0/bundler/gems/devise-secure_password-*
    rm -rf /gems/ruby/3.4.0/cache/bundler/git/devise-secure_password-*
    bundle install
  }
else
  echo "All gems already installed, skipping bundle install"
fi

echo "Installing pnpm dependencies..."
# Don't prune store - preserve cached packages
# Use cached installations instead of --force
pnpm install

echo "Ready to run Vite development server."

exec "$@"
