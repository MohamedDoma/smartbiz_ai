"""
SmartBiz AI — Router package.

Re-exports every router so main.py can do:
    from app.routers import auth, workspaces, ...
"""

from app.routers import (
    accounting,
    ai,
    approvals,
    auth,
    inventory,
    invoices,
    notifications,
    orders,
    payments,
    platform_admin,
    products,
    sync,
    users,
    workspaces,
)

__all__ = [
    "auth",
    "workspaces",
    "users",
    "products",
    "inventory",
    "orders",
    "invoices",
    "payments",
    "accounting",
    "ai",
    "notifications",
    "approvals",
    "sync",
    "platform_admin",
]
