#FROM chatwoot:development
FROM click2run/chatwoot:development

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Install build dependencies needed for native gem compilation
# postgresql-dev: Required for pg gem compilation
# build-base, yaml-dev, clang-dev, llvm-dev: Required for other native gems
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    yaml-dev \
    clang-dev \
    llvm-dev \
    rust \
    cargo

# Configure bundle to build native gems
RUN bundle config set --local force_ruby_platform true

# Regenerate bundler binstubs to match current Gemfile.lock
# Ensure correct bundler version and install all gems (including dev/test)
RUN gem install bundler -v 2.7.2 && \
    bundle install && \
    bundle binstubs bundler --force && \
    bundle binstubs vite_ruby --force && \
    chmod +x docker/entrypoints/vite.sh

EXPOSE 3036
CMD ["bin/vite", "dev"]
