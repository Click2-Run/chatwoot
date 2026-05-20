# frozen_string_literal: true

# == Schema Information
#
# Table name: propriacloud_embedded_signup_sessions
#
#  id                  :bigint           not null, primary key
#  account_id          :bigint           not null
#  minha_session_id    :string           (unique)
#  instance_id         :string           not null
#  intended_inbox_name :string           not null
#  phone_number        :string
#  mark_as_read        :boolean          default(TRUE), not null
#  status              :string           default('pending'), not null
#  inbox_id            :bigint           (set on success)
#  last_error          :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Holds the in-flight signup-session record after Chatwoot calls
# `POST minha:/api/external/whatsapp/v1/signup-sessions` to mint the public
# URL. Completion is observed via the existing whatsapp-api → chatwoot event
# flow (instance.updated / pairing.* events update `provider_connection` on
# the channel) — no callback to chatwoot is involved.
class PropriacloudEmbeddedSignupSession < ApplicationRecord
  STATUSES = %w[pending completed failed expired].freeze

  belongs_to :account
  belongs_to :inbox, optional: true

  validates :instance_id, presence: true
  validates :intended_inbox_name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
end
