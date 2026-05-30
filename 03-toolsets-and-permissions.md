# Toolsets and Permissions

Toolsets define what the agent can actually do. Document them by risk category, not just by availability.

## Common core toolsets

For an operator-grade profile, the usual core is terminal, file, code execution, web, browser, vision, skills, memory, session search, todo, delegation, cronjob, messaging, and TTS.

## Optional toolsets

Enable only when there is a real operating need: image generation, video, Home Assistant, Spotify, social media, and platform admin toolsets.

## MCP toolsets

Document each MCP server: name, command or URL, transport, auth mode, enabled tool selection, test result, and reload/restart caveat.

For GBrain, the done bar is: MCP connects, tools are discovered, stats/search/query work against the intended brain.

## Risk model

- **Read-only:** search, read files, inspect state.
- **Local write:** write docs, patch files, create artifacts.
- **External side effects:** send messages, email, post publicly, change calendar/Drive/docs, open PRs, update issues.
- **Sensitive/destructive:** credentials, permissions, purchases, deletion, security posture.

External side effects require explicit approval from the human owner unless a narrower pre-approved automation contract exists.

## Messaging boundary

Even if the messaging toolset is enabled, the agent should not send real-world messages on the user's behalf without explicit approval. Drafts and recommendations are safe; sending is not.
