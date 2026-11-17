# frozen_string_literal: true
require File.expand_path('../../test_helper', __FILE__)

class RegistrationTest < Redmine::IntegrationTest
  include AgentConnectTestSetup
  fixtures :users, :email_addresses, :user_preferences, :roles
  SECOND = 'https://example.com/other'

  def setup
    super
    Setting.rest_api_enabled = '1'
    mcp_settings('allowed_redirect_uris' => "#{CALLBACK}\n#{SECOND}")
    RedmineAgentConnect::Backend.stubs(:available?).returns(true)
    reset_oauth_tables
  end

  def register(name: 'Claude', uris: [CALLBACK], scope: nil)
    post '/agent_connect/register', params: {client_name: name, redirect_uris: uris, scope: scope}.compact.to_json,
      headers: {'Content-Type' => 'application/json'}
    assert_response :created
    JSON.parse(response.body)
  end

  def test_repeat_registration_reuses_one_public_application
    first = register
    3.times { assert_equal first['client_id'], register['client_id'] }
    assert_equal 1, Doorkeeper::Application.count
  end

  def test_changed_scope_setting_registers_a_new_application
    first = register
    mcp_settings('allowed_redirect_uris' => CALLBACK, 'scopes' => 'view_issues')
    second = register
    assert_not_equal first['client_id'], second['client_id']
    assert_equal 'view_issues', second['scope']
  end

  def test_uri_order_duplicates_and_requested_scope_do_not_create_duplicates
    first = register(uris: [CALLBACK, SECOND])
    second = register(uris: [SECOND, CALLBACK, SECOND], scope: 'admin view_issues')
    assert_equal first['client_id'], second['client_id']
    assert_equal 1, Doorkeeper::Application.count
  end

  def test_different_metadata_produces_distinct_application
    first = register
    assert_not_equal first['client_id'], register(name: 'Other client')['client_id']
    assert_not_equal first['client_id'], register(uris: [SECOND])['client_id']
    assert_equal 3, Doorkeeper::Application.count
  end

  def test_repeat_registration_preserves_existing_user_tokens
    app = Doorkeeper::Application.find_by!(uid: register['client_id'])
    token = Doorkeeper::AccessToken.create!(application_id: app.id, resource_owner_id: 1,
      scopes: SCOPES, expires_in: 3600)
    assert_equal app.uid, register['client_id']
    assert_nil token.reload.revoked_at
    assert_equal 1, Doorkeeper::AccessToken.count
  end

  def test_admin_edited_client_is_not_returned_for_old_registration_metadata
    app = Doorkeeper::Application.find_by!(uid: register['client_id'])
    app.update!(redirect_uri: SECOND, confidential: true)
    replacement = register
    assert_not_equal app.uid, replacement['client_id']
    assert_nil app.reload.agent_connect_key
    current = Doorkeeper::Application.find_by!(uid: replacement['client_id'])
    assert_equal CALLBACK, current.redirect_uri
    assert_not current.confidential?
    assert_equal replacement['client_id'], register['client_id']
  end

  def test_database_unique_key_prevents_concurrent_duplicate_insert
    app = Doorkeeper::Application.find_by!(uid: register['client_id'])
    assert_raises(ActiveRecord::RecordNotUnique) do
      Doorkeeper::Application.transaction(requires_new: true) do
        Doorkeeper::Application.create!(name: 'Duplicate', redirect_uri: CALLBACK,
          scopes: SCOPES, confidential: false, agent_connect_key: app.agent_connect_key)
      end
    end
    assert_equal 1, Doorkeeper::Application.count
  end

  def legacy_app(name, scopes, confidential: false)
    app = Doorkeeper::Application.new(name: name, uid: SecureRandom.hex(16), secret: SecureRandom.hex(16),
                                      redirect_uri: CALLBACK, scopes: scopes, confidential: confidential)
    app.save!(validate: false) # "mcp_tools" is no longer a configured Doorkeeper scope
    app
  end

  def test_retire_migration_removes_redmine_mcp_connections_only
    require_relative '../../db/migrate/002_retire_redmine_mcp_applications'
    legacy = legacy_app('Old MCP', 'mcp_tools')
    legacy_token = Doorkeeper::AccessToken.create!(application_id: legacy.id, resource_owner_id: 1, scopes: 'view_issues', expires_in: 3600)
    mixed = legacy_app('Manual', 'mcp_tools view_issues', confidential: true)
    current = Doorkeeper::Application.find_by!(uid: register['client_id'])
    other = Doorkeeper::Application.create!(name: 'Azure SSO', redirect_uri: SECOND, scopes: '', confidential: true)
    role = Role.find(1)
    role.permissions = role.permissions + [:mcp_tools]
    role.save!(validate: false)
    assert_includes role.reload.permissions, :mcp_tools

    ActiveRecord::Migration.suppress_messages { RetireRedmineMcpApplications.new.up }

    assert_not Doorkeeper::Application.exists?(legacy.id)
    assert_not Doorkeeper::AccessToken.exists?(legacy_token.id)
    assert_equal 'view_issues', mixed.reload.scopes.to_s
    assert mixed.valid?
    assert Doorkeeper::Application.exists?(current.id)
    assert Doorkeeper::Application.exists?(other.id)
    assert_not_includes role.reload.permissions, :mcp_tools
  end
end
