# UpKeep MCP — Read-Only

Read-only MCP server for UpKeep maintenance management. Designed for Claude Desktop / Teams.

## Accounts

| Account | Env Vars | Customers |
|---------|----------|-----------|
| `bancroft` | `UPKEEP_EMAIL` / `UPKEEP_PASSWORD` | Bancroft (single) |
| `multisite` | `UPKEEP_EMAIL_2` / `UPKEEP_PASSWORD_2` | PennReach, J-ADD, Arc Mercer, PCDI, Newgrange |

## Tools

| Tool | Description |
|------|-------------|
| `list_work_orders` | Query work orders with filters (status, category, location, date) |
| `get_work_order` | Full details for a single work order |
| `list_locations` | All locations in an account |
| `get_location` | Full details for a single location |
| `list_users` | All users/technicians |
| `list_assets` | Equipment/assets, filterable by location |
| `get_wo_counts_by_status` | Dashboard summary — WO counts by status |
| `list_preventive_maintenance` | Recurring PM schedules |

## Claude Desktop Setup

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "upkeep": {
      "command": "python",
      "args": ["C:\\DCFG\\tools\\upkeep-mcp\\server.py"],
      "env": {
        "UPKEEP_EMAIL": "your-bancroft-email",
        "UPKEEP_PASSWORD": "your-bancroft-password",
        "UPKEEP_EMAIL_2": "your-multisite-email",
        "UPKEEP_PASSWORD_2": "your-multisite-password"
      }
    }
  }
}
```

## Security

- **Read-only** — no POST/PUT/DELETE/PATCH calls to UpKeep
- **No writes to any system** — pure query tools
- Session tokens cached in memory only (not persisted to disk)
