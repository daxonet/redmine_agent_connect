# frozen_string_literal: true

# Replaces the archived redmine_mcp plugin. Its applications carry the
# "mcp_tools" scope, which no longer exists once that plugin is removed and
# which grants nothing in RedmineUP Agent. Remove those connections (users
# reconnect once) and strip the scope elsewhere so the remaining OAuth
# applications stay valid. Other applications, e.g. Azure SSO, are untouched.
#
# redmine_mcp's own tables and columns (mcp_oauth_*, mcp_registration_key,
# mcp_refresh_expires_at) are left in place; see README for optional cleanup.
class RetireRedmineMcpApplications < ActiveRecord::Migration[7.2]
  LEGACY = %w[mcp_tools mcp:tools].freeze

  def up
    Doorkeeper::Application.where(scopes: LEGACY).find_each(&:destroy!)
    Doorkeeper::Application.where('scopes LIKE ?', '%mcp%').find_each do |app|
      kept = app.scopes.to_s.split - LEGACY
      app.update_column(:scopes, kept.join(' ')) if kept != app.scopes.to_s.split
    end
    Role.find_each { |role| role.remove_permission!(:mcp_tools) if role.permissions.include?(:mcp_tools) }
  end

  def down
    # Deleted connections are re-created by reconnecting.
  end
end
