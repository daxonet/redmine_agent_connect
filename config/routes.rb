# frozen_string_literal: true

# Plugins load in directory order, so these discovery routes take precedence
# over RedmineUP Agent's own (redmine_agent_connect < redmineup_agent).
# The MCP endpoint itself (/mcp) is served by RedmineUP Agent.
get '.well-known/oauth-authorization-server', to: 'agent_connect_oauth#authorization_server_metadata', format: false
get '.well-known/oauth-protected-resource', to: 'agent_connect_oauth#protected_resource_metadata', format: false
get '.well-known/oauth-protected-resource/*path', to: 'agent_connect_oauth#protected_resource_metadata', format: false

post 'agent_connect/register', to: 'agent_connect_oauth#register', as: :agent_connect_register

delete 'oauth/applications/:application_id/agent_connect_authorizations/:user_id',
       to: 'agent_connect_authorizations#destroy', as: :agent_connect_authorization
