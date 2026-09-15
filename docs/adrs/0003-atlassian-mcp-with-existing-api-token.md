# 0003: Use MCP Atlassian with the existing work API token

Date: 2026-09-15
Status at creation: accepted
Supersedes: the MCP transport choice in 0002-work-profile-and-runtime-atlassian-auth.md

## Context

The official remote server accepted initialization but its authenticated
getAccessibleAtlassianResources call rejected the current work token: the
session token has no scope claim required for that operation. Initialization
and tool listing therefore did not establish usable authenticated access.
Official ACLI and mcp-atlassian 0.23.1 both completed Jira reads with this token.

## Decision

Use pinned pipx:mcp-atlassian 0.23.1 in work images. Keep the same client
registration and scoped fnox launcher. Translate the existing Atlassian URL,
email and token to the server's Jira and Confluence environment variables.
The token is never passed as an argument or written to client configuration.
This is the community MCP Atlassian server, not Atlassian's remote server.

## Alternatives and consequences

Using the official remote server would require changing the token's scopes
and possibly organization settings. The community server satisfies the
requested MCP access with current credentials, at the cost of installing
and maintaining a pinned local Python service. Update its pin deliberately.

## Verification

The live preflight completed an authenticated jira_search with limit 1.
The final sandboxes verifier must repeat initialization, discovery and the
read through the installed client configuration on the final published image.
Native credential, URL mapping, argument and cleanup tests remain required.
