"""
UpKeep MCP — Read-only UpKeep API server for Claude Desktop / Teams.

Provides read-only access to UpKeep work orders, locations, users, and assets
across two accounts: Bancroft (single-customer) and Multi-site (PennReach, J-ADD, etc.)

Auth: UpKeep email/password → session token (cached in memory).
Credentials via environment variables:
  UPKEEP_EMAIL / UPKEEP_PASSWORD         — Bancroft account
  UPKEEP_EMAIL_2 / UPKEEP_PASSWORD_2    — Multi-site account

No writes. Every tool is a GET request.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime
from typing import Any, Optional

import httpx
from mcp.server.fastmcp import FastMCP

# ─── Constants ────────────────────────────────────────────────────────────────
UPKEEP_API = "https://api.onupkeep.com/api/v2"

ACCOUNTS = {
    "bancroft": {
        "label": "Bancroft",
        "email_var": "UPKEEP_EMAIL",
        "password_var": "UPKEEP_PASSWORD",
    },
    "multisite": {
        "label": "Multi-Site (PennReach, J-ADD, Arc Mercer, PCDI, Newgrange)",
        "email_var": "UPKEEP_EMAIL_2",
        "password_var": "UPKEEP_PASSWORD_2",
    },
}

# ─── Category labels ──────────────────────────────────────────────────────────
CATEGORY_LABELS = {
    "Inspection": "Inspection",
    "Inspections": "Inspection",
    "Preventative": "Preventative",
    "Punchlist": "Punchlist",
    "Painting - Punch List": "Punchlist",
    "Plumbing": "Plumbing",
    "Plumbing - General": "Plumbing",
    "Plumbing - Specialty": "Plumbing",
    "Painting": "Painting",
    "Electrical": "Electrical",
    "HVAC": "HVAC",
    "General Maintenance": "General Maintenance",
    "Safety": "Safety",
    "Move Requests": "Move Requests",
}

WO_STATUS_MAP = {
    "open": "Open",
    "onHold": "On Hold",
    "inProgress": "In Progress",
    "closed": "Closed",
}

# ─── Auth ─────────────────────────────────────────────────────────────────────
_token_cache: dict[str, str] = {}


def _get_token(account: str) -> str:
    """Get or refresh UpKeep session token for an account."""
    if account in _token_cache:
        return _token_cache[account]

    acct = ACCOUNTS.get(account)
    if not acct:
        raise ValueError(f"Unknown account: {account}. Use 'bancroft' or 'multisite'.")

    email = os.environ.get(acct["email_var"])
    password = os.environ.get(acct["password_var"])
    if not email or not password:
        raise ValueError(
            f"Missing credentials for {acct['label']}. "
            f"Set {acct['email_var']} and {acct['password_var']} environment variables."
        )

    resp = httpx.post(
        f"{UPKEEP_API}/auth",
        json={"email": email, "password": password},
        timeout=15,
    )
    resp.raise_for_status()
    data = resp.json()
    token = data.get("result", {}).get("sessionToken")
    if not token:
        raise ValueError(f"UpKeep auth failed for {acct['label']}: {json.dumps(data)[:200]}")

    _token_cache[account] = token
    return token


def _get(account: str, path: str, params: dict | None = None) -> dict:
    """Make authenticated GET request to UpKeep API."""
    token = _get_token(account)
    resp = httpx.get(
        f"{UPKEEP_API}{path}",
        headers={"Session-Token": token},
        params=params or {},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


def _paginate(account: str, path: str, params: dict | None = None, max_pages: int = 10) -> list:
    """Paginate through UpKeep API results."""
    all_results = []
    p = dict(params or {})
    p.setdefault("limit", "100")

    for page in range(max_pages):
        p["offset"] = str(page * int(p["limit"]))
        data = _get(account, path, p)
        results = data.get("results", [])
        all_results.extend(results)
        if len(results) < int(p["limit"]):
            break

    return all_results


# ─── MCP Server ───────────────────────────────────────────────────────────────
mcp = FastMCP(
    "upkeep",
    description="Read-only access to UpKeep work orders, locations, users, and assets. Two accounts: bancroft (single customer) and multisite (PennReach, J-ADD, Arc Mercer, PCDI, Newgrange).",
)


@mcp.tool()
def list_work_orders(
    account: str = "bancroft",
    status: str = "",
    category: str = "",
    location_id: str = "",
    assigned_to_id: str = "",
    created_after: str = "",
    limit: int = 50,
) -> str:
    """
    List work orders from UpKeep. Returns summary rows.

    Args:
        account: "bancroft" or "multisite"
        status: Filter by status: "open", "onHold", "inProgress", "closed"
        category: Filter by category name (e.g. "Inspection", "Plumbing")
        location_id: Filter by UpKeep location ID
        assigned_to_id: Filter by assigned user ID
        created_after: ISO date string (e.g. "2026-01-01") — only WOs created after this date
        limit: Max results (default 50, max 200)
    """
    params: dict[str, str] = {"limit": str(min(limit, 200))}
    if status:
        params["status"] = status
    if category:
        params["category"] = category
    if location_id:
        params["location"] = location_id
    if assigned_to_id:
        params["assignedTo"] = assigned_to_id
    if created_after:
        params["createdAt[gte]"] = created_after

    results = _paginate(account, "/work-orders", params, max_pages=max(1, limit // 100 + 1))

    rows = []
    for wo in results[:limit]:
        rows.append({
            "id": wo.get("id"),
            "title": wo.get("title", ""),
            "status": WO_STATUS_MAP.get(wo.get("status", ""), wo.get("status", "")),
            "category": wo.get("category", ""),
            "priority": wo.get("priority", ""),
            "location": wo.get("location", {}).get("name", "") if isinstance(wo.get("location"), dict) else "",
            "assignedTo": wo.get("assignedToUser", {}).get("name", "") if isinstance(wo.get("assignedToUser"), dict) else "",
            "createdAt": wo.get("createdAt", ""),
            "dueDate": wo.get("dueDate", ""),
        })

    return json.dumps({"account": ACCOUNTS[account]["label"], "count": len(rows), "work_orders": rows}, indent=2)


@mcp.tool()
def get_work_order(account: str = "bancroft", work_order_id: str = "") -> str:
    """
    Get full details for a single work order.

    Args:
        account: "bancroft" or "multisite"
        work_order_id: The UpKeep work order ID
    """
    if not work_order_id:
        return json.dumps({"error": "work_order_id is required"})

    data = _get(account, f"/work-orders/{work_order_id}")
    wo = data.get("result", data)

    return json.dumps({
        "id": wo.get("id"),
        "title": wo.get("title"),
        "description": wo.get("description"),
        "status": WO_STATUS_MAP.get(wo.get("status", ""), wo.get("status", "")),
        "category": wo.get("category"),
        "priority": wo.get("priority"),
        "location": wo.get("location"),
        "assignedToUser": wo.get("assignedToUser"),
        "createdByUser": wo.get("createdByUser"),
        "createdAt": wo.get("createdAt"),
        "updatedAt": wo.get("updatedAt"),
        "dueDate": wo.get("dueDate"),
        "completedDate": wo.get("completedDate"),
        "estimatedDuration": wo.get("estimatedDuration"),
        "actualDuration": wo.get("actualDuration"),
        "parts": wo.get("parts", []),
        "customFields": wo.get("customFields", []),
    }, indent=2)


@mcp.tool()
def list_locations(account: str = "bancroft", search: str = "", limit: int = 100) -> str:
    """
    List all locations in the UpKeep account.

    Args:
        account: "bancroft" or "multisite"
        search: Optional search string to filter by name
        limit: Max results (default 100)
    """
    params: dict[str, str] = {"limit": str(min(limit, 200))}
    if search:
        params["name"] = search

    results = _paginate(account, "/locations", params, max_pages=5)

    rows = []
    for loc in results[:limit]:
        rows.append({
            "id": loc.get("id"),
            "name": loc.get("name", ""),
            "address": loc.get("address", ""),
            "city": loc.get("city", ""),
            "state": loc.get("state", ""),
            "zip": loc.get("zipCode", ""),
            "createdAt": loc.get("createdAt", ""),
        })

    return json.dumps({"account": ACCOUNTS[account]["label"], "count": len(rows), "locations": rows}, indent=2)


@mcp.tool()
def get_location(account: str = "bancroft", location_id: str = "") -> str:
    """
    Get full details for a single location.

    Args:
        account: "bancroft" or "multisite"
        location_id: The UpKeep location ID
    """
    if not location_id:
        return json.dumps({"error": "location_id is required"})

    data = _get(account, f"/locations/{location_id}")
    loc = data.get("result", data)

    return json.dumps({
        "id": loc.get("id"),
        "name": loc.get("name"),
        "address": loc.get("address"),
        "city": loc.get("city"),
        "state": loc.get("state"),
        "zip": loc.get("zipCode"),
        "phone": loc.get("phone"),
        "createdAt": loc.get("createdAt"),
        "customFields": loc.get("customFields", []),
    }, indent=2)


@mcp.tool()
def list_users(account: str = "bancroft") -> str:
    """
    List all users (technicians, admins) in the UpKeep account.

    Args:
        account: "bancroft" or "multisite"
    """
    results = _paginate(account, "/users", {"limit": "200"}, max_pages=3)

    rows = []
    for u in results:
        rows.append({
            "id": u.get("id"),
            "name": u.get("name", "") or f"{u.get('firstName', '')} {u.get('lastName', '')}".strip(),
            "email": u.get("email", ""),
            "role": u.get("role", ""),
            "phone": u.get("phone", ""),
        })

    return json.dumps({"account": ACCOUNTS[account]["label"], "count": len(rows), "users": rows}, indent=2)


@mcp.tool()
def list_assets(account: str = "bancroft", location_id: str = "", search: str = "", limit: int = 100) -> str:
    """
    List assets (equipment) in the UpKeep account.

    Args:
        account: "bancroft" or "multisite"
        location_id: Optional — filter by location
        search: Optional search string
        limit: Max results (default 100)
    """
    params: dict[str, str] = {"limit": str(min(limit, 200))}
    if location_id:
        params["location"] = location_id
    if search:
        params["name"] = search

    results = _paginate(account, "/assets", params, max_pages=5)

    rows = []
    for a in results[:limit]:
        rows.append({
            "id": a.get("id"),
            "name": a.get("name", ""),
            "model": a.get("model", ""),
            "serialNumber": a.get("serialNumber", ""),
            "location": a.get("location", {}).get("name", "") if isinstance(a.get("location"), dict) else "",
            "category": a.get("category", ""),
            "status": a.get("status", ""),
        })

    return json.dumps({"account": ACCOUNTS[account]["label"], "count": len(rows), "assets": rows}, indent=2)


@mcp.tool()
def get_wo_counts_by_status(account: str = "bancroft") -> str:
    """
    Get work order counts grouped by status. Useful for dashboards and summaries.

    Args:
        account: "bancroft" or "multisite"
    """
    counts = {}
    for status in ["open", "onHold", "inProgress", "closed"]:
        data = _get(account, "/work-orders", {"status": status, "limit": "1"})
        counts[WO_STATUS_MAP.get(status, status)] = data.get("totalCount", 0)

    return json.dumps({"account": ACCOUNTS[account]["label"], "counts": counts}, indent=2)


@mcp.tool()
def list_preventive_maintenance(account: str = "bancroft", limit: int = 50) -> str:
    """
    List preventive maintenance triggers (recurring work order schedules).

    Args:
        account: "bancroft" or "multisite"
        limit: Max results (default 50)
    """
    results = _paginate(account, "/preventive-maintenance", {"limit": str(min(limit, 200))}, max_pages=3)

    rows = []
    for pm in results[:limit]:
        rows.append({
            "id": pm.get("id"),
            "title": pm.get("title", ""),
            "category": pm.get("category", ""),
            "frequency": pm.get("frequency", ""),
            "location": pm.get("location", {}).get("name", "") if isinstance(pm.get("location"), dict) else "",
            "assignedTo": pm.get("assignedToUser", {}).get("name", "") if isinstance(pm.get("assignedToUser"), dict) else "",
            "nextDueDate": pm.get("nextDueDate", ""),
        })

    return json.dumps({"account": ACCOUNTS[account]["label"], "count": len(rows), "schedules": rows}, indent=2)


# ─── Entry point ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    mcp.run(transport="stdio")
