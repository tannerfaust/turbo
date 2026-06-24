# Turbotask MCP

Local MCP server for the Turbotask macOS app. It reads and writes the same JSON workspace used by the app:

`~/Library/Application Support/TurboTasker/workspace.json`

The server uses stdio, so Codex, Claude Desktop, and Cursor can launch it as a local MCP command.

## Setup

```sh
cd mcp/turbotask-mcp
npm install
npm run build
```

## Run

```sh
node /Users/mediaalamedia/Turbo/mcp/turbotask-mcp/dist/server.js
```

Optional environment variables:

- `TURBOTASK_WORKSPACE`: absolute path to a workspace JSON file.
- `TURBOTASK_APP_SUPPORT_DIR`: directory containing `workspace.json` and `workspace.backup.json`.

## Client Config

Claude Desktop:

```json
{
  "mcpServers": {
    "turbotask": {
      "command": "node",
      "args": ["/Users/mediaalamedia/Turbo/mcp/turbotask-mcp/dist/server.js"]
    }
  }
}
```

Cursor:

```json
{
  "mcpServers": {
    "turbotask": {
      "command": "node",
      "args": ["/Users/mediaalamedia/Turbo/mcp/turbotask-mcp/dist/server.js"]
    }
  }
}
```

Codex:

```json
{
  "mcpServers": {
    "turbotask": {
      "command": "node",
      "args": ["/Users/mediaalamedia/Turbo/mcp/turbotask-mcp/dist/server.js"]
    }
  }
}
```

## Exposed Surface

Resources:

- `turbotask://workspace`
- `turbotask://tasks/now`
- `turbotask://tasks/all`
- `turbotask://history/recent`

Tools:

- `workspace_status`
- `read_workspace`
- `list_jobs`
- `list_projects`
- `list_operations`
- `list_tasks`
- `get_task`
- `create_job`
- `create_project`
- `create_operation`
- `create_task`
- `update_task`
- `set_task_status`
- `toggle_task_now`
- `archive_task`
- `delete_task`
- `log_activity`
- `search_workspace`

Prompts:

- `daily_plan`
- `task_breakdown`
