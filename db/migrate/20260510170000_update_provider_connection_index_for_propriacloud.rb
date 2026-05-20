# frozen_string_literal: true

# Replaces the stale conditional GIN index on `channel_whatsapp.provider_connection`
# that was scoped to `click2run` (the legacy provider name) so jsonb path
# queries against `propriacloud` rows again hit the index instead of falling
# back to a sequential scan.
#
# Idempotent: drops the existing index by name first, then re-adds with the
# canonical predicate. `click2run` rows no longer exist in production
# (rename happened pre-fork-merge) so the predicate is updated rather than
# extended.
class UpdateProviderConnectionIndexForPropriacloud < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    remove_index :channel_whatsapp, name: 'index_channel_whatsapp_provider_connection', if_exists: true

    add_index :channel_whatsapp, :provider_connection,
              using: :gin,
              where: "provider IN ('baileys', 'zapi', 'whatsmeow', 'propriacloud')",
              name: 'index_channel_whatsapp_provider_connection',
              algorithm: :concurrently
  end

  def down
    remove_index :channel_whatsapp, name: 'index_channel_whatsapp_provider_connection', if_exists: true

    add_index :channel_whatsapp, :provider_connection,
              using: :gin,
              where: "provider IN ('baileys', 'zapi', 'whatsmeow', 'click2run')",
              name: 'index_channel_whatsapp_provider_connection',
              algorithm: :concurrently
  end
end
