# frozen_string_literal: true

class AddAgentConnectColumns < ActiveRecord::Migration[7.2]
  def change
    # Identifies applications this plugin registered (DCR or CIMD) and makes
    # repeated registrations idempotent.
    add_column :oauth_applications, :agent_connect_key, :string, limit: 64
    add_index :oauth_applications, :agent_connect_key, unique: true
    # Rolling 30-day refresh lifetime for those applications.
    add_column :oauth_access_tokens, :agent_connect_refresh_expires_at, :datetime
  end
end
