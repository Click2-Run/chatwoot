#FROM chatwoot:development
FROM click2run/chatwoot:development

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Regenerate bundler binstubs to match current Gemfile.lock
# Ensure correct bundler version
RUN gem install bundler -v 2.7.2 && \
    bundle install && \
    bundle binstubs bundler --force && \
    bundle binstubs vite_ruby --force && \
    chmod +x docker/entrypoints/vite.sh

EXPOSE 3036
CMD ["bin/vite", "dev"]
