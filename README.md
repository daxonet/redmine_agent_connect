# Redmine Agent Connect

Zero-configuration sign-in for the **RedmineUP Agent** MCP server. Requires Redmine 7.0+ and RedmineUP Agent (`redmineup_agent`) with its MCP server enabled.

RedmineUP Agent serves `/mcp` and all tools, including the RedmineUP plugin integrations. It expects an administrator to create an OAuth application for every client and hand out a client ID and secret. This plugin removes that step: users enter `https://<redmine>/mcp` in their AI client and sign in with their Redmine account.

**Lifecycle:** this plugin only fills a gap in RedmineUP Agent. If RedmineUP Agent adds dynamic registration or client metadata documents itself, uninstall this plugin (see *Uninstall*). It replaces the archived [daxonet/redmine_mcp](https://github.com/daxonet/redmine_mcp). Its last standalone MCP server with built-in tools is tag `v1.2.0`.

| Client | Sign-in method | Administrator work |
|---|---|---|
| claude.ai, Claude Desktop, mobile | Client ID Metadata Document (falls back to DCR) | none |
| Claude Code | Client ID Metadata Document, loopback redirect on any port | none |
| ChatGPT | Client ID Metadata Document or DCR | none |
| VS Code / GitHub Copilot | Dynamic Client Registration (DCR) | none |
| Microsoft Copilot and other clients that need a secret | — | create an application in **Administration → Applications** |

## What it provides

- **Discovery metadata.** `/.well-known/oauth-authorization-server` and `/.well-known/oauth-protected-resource[/mcp]` point clients to Redmine's native OAuth server (`/oauth/authorize`, `/oauth/token`, `/oauth/revoke`) and advertise the MCP scopes. These routes load before RedmineUP Agent's own discovery documents and take precedence over them.
- **Dynamic Client Registration** at `/agent_connect/register`, for public clients (`token_endpoint_auth_method: none`). Callback URLs must match the trusted list. Identical registrations reuse one application.
- **Client ID Metadata Documents.** When a client's `client_id` is an https URL on a trusted host, the plugin fetches it (3 s timeout, 16 KB limit, refreshed hourly) and stores it as a public application whose client ID is that URL. The document must offer `none` as a token endpoint auth method, though it may prefer another: ChatGPT declares `private_key_jwt` and also offers `none`. It must also support `authorization_code`. Other grant types it declares are ignored.
- **Token policy for these applications only:** S256 PKCE required, one-hour access tokens, rotating 30-day refresh tokens, and locked users rejected. Other OAuth applications keep Redmine's defaults.
- **Bearer challenge.** When *Authentication required* is enabled, Redmine core answers anonymous `/mcp` requests with a Basic challenge before RedmineUP Agent runs. This plugin lets the `/mcp` action answer with its own `Bearer resource_metadata=…` challenge instead. That action still authenticates every request; the rest of Redmine keeps requiring login.
- **Loopback redirects.** `http://localhost/...` redirects match on any port, as Claude Code requires. Doorkeeper already does this for `127.0.0.1`.
- **Revocation.** Administrators can revoke one user's access on the application page in **Administration → Applications**. Users can revoke their own access under **My account → Authorized applications**.

## Scopes

Self-registered clients receive the scopes from the plugin setting. When that setting is empty, they receive RedmineUP Agent's MCP scope list. `admin` is never granted. If a client requests scopes the application does not hold, the request is narrowed to the application's scopes. A token can only restrict a user; the user still acts within their own Redmine project permissions.

## Setup

1. **Administration → Settings → API**: enable the REST web service.
2. **Administration → Settings → General**: set *Host name and path* to the public host. RedmineUP Agent builds its `WWW-Authenticate` discovery pointer from this value.
3. **Administration → Plugins → RedmineUP Agent**: enable *MCP server*.
4. **Administration → Plugins → Redmine Agent Connect**: check that the status shows yes three times.
   - *Trusted callback URLs*: one per line. `*` matches one run of characters without `/ ? # @`. The defaults cover claude.ai, Claude Code, ChatGPT and VS Code. An empty list disables DCR.
   - *Trusted client metadata hosts*: default `claude.ai` and `chatgpt.com`. Redmine needs outbound HTTPS to these hosts. An empty list disables CIMD, and clients then fall back to DCR.
   - *Scopes*: leave empty to follow RedmineUP Agent.

To check the setup, request `https://<redmine>/.well-known/oauth-protected-resource/mcp` without signing in. It should return RedmineUP scopes such as `view_issues`, and never `admin`.

## Migrating from redmine_mcp

1. Back up the database.
2. Remove `redmine_mcp`. Deploy this plugin together with RedmineUP Agent, then run `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`.
3. Migration `RetireRedmineMcpApplications`:
   - deletes applications whose only scope is `mcp_tools`, together with their grants and tokens. Those tokens grant nothing in RedmineUP Agent, so each user removes and re-adds the connector once.
   - removes `mcp_tools` from any other application and from roles.
   - leaves unrelated applications, such as Azure SSO, untouched.
4. redmine_mcp's tables and columns stay in place. Once you no longer need a rollback, you can drop them:

```sql
DROP TABLE mcp_oauth_tokens, mcp_oauth_auth_codes, mcp_oauth_clients;
ALTER TABLE oauth_applications DROP INDEX index_oauth_applications_on_mcp_registration_key, DROP COLUMN mcp_registration_key;
ALTER TABLE oauth_access_tokens DROP COLUMN mcp_refresh_expires_at;
DELETE FROM schema_migrations WHERE version LIKE '%-redmine_mcp';
```

Rollback: restore the backup, deploy `redmine_mcp` v1.2.0 and disable RedmineUP Agent's MCP server. Both plugins claim the same URLs.

## Uninstall

Run `bundle exec rake redmine:plugins:migrate NAME=redmine_agent_connect VERSION=0 RAILS_ENV=production`, then remove the plugin directory. This removes the plugin's columns. Its registered applications remain under **Administration → Applications** until you delete them.

## Tests

Run `RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=redmine_agent_connect`. `test/integration/redmineup_agent_connect_test.rb` runs end to end against RedmineUP Agent (DCR → consent → token → `/mcp` tools) when the agent is installed, and is skipped otherwise, as in public CI.
