# frozen_string_literal: true

# Creates the pending-session record that bridges the start-of-signup HTTP
# call (which returns a propria.cloud-hosted URL) and the asynchronous
# webhook callback that finalizes the inbox once the customer completes
# Meta Embedded Signup. Each row owns its instance_id + callback_secret +
# intended inbox metadata until the callback either creates the channel
# or the row times out.
class CreatePropriacloudEmbeddedSignupSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :propriacloud_embedded_signup_sessions do |t|
      t.references :account, null: false, foreign_key: true, index: true
      # Minha-issued session id (uuid string). Returned by the callback and
      # used to look the row up. Unique across the table; null until minha
      # acknowledges the create-session call.
      t.string :minha_session_id, index: { unique: true }
      # Stable identifier the customer's eventual instance carries on
      # whatsapp-api. Chatwoot generates this and passes to minha.
      t.string :instance_id, null: false
      # User-provided inbox configuration carried across the round trip.
      t.string :intended_inbox_name, null: false
      t.string :phone_number
      t.boolean :mark_as_read, default: true, null: false
      # Status lifecycle: pending → completed | failed | expired
      t.string :status, null: false, default: 'pending', index: true
      # FK to the channel that was created on success (nullable until then).
      t.references :inbox, foreign_key: true
      # Last error message if status='failed' (for diagnosis in the UI).
      t.text :last_error
      t.timestamps
    end

    add_index :propriacloud_embedded_signup_sessions, %i[account_id status]
  end
end
