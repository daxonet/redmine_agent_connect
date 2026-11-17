# frozen_string_literal: true

require_relative 'lib/redmine_agent_connect/backend'
require_relative 'lib/redmine_agent_connect/redirect_policy'
require_relative 'lib/redmine_agent_connect/client_metadata_document'
require_relative 'lib/redmine_agent_connect/dynamic_client_registration'

Redmine::Plugin.register :redmine_agent_connect do
  name        'Redmine Agent Connect'
  author      'DAXONET'
  description 'Zero-configuration OAuth sign-in (dynamic registration, client metadata documents) for the RedmineUP Agent MCP server'
  version     '1.0.1'
  url         'https://github.com/daxonet/redmine_agent_connect'

  requires_redmine version_or_higher: '7.0'

  settings default: {
    'allowed_redirect_uris' => <<~URIS,
      https://claude.ai/api/mcp/auth_callback
      http://localhost/callback
      http://localhost:*/callback
      http://127.0.0.1/callback
      http://127.0.0.1:*/callback
      https://chatgpt.com/connector_platform_oauth_redirect
      https://chatgpt.com/connector/oauth/*
      http://127.0.0.1:33418
      http://127.0.0.1:33418/
      https://vscode.dev/redirect
    URIS
    'cimd_trusted_hosts' => "claude.ai\nchatgpt.com\n",
    'scopes' => ''
  }, partial: 'settings/agent_connect_settings'
end

require_relative 'lib/redmine_agent_connect/native_oauth'
