"""
Platform Admin router — super-admin operations, tenant management.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/platform-admin", tags=["Platform Admin"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the platform-admin module."""
    return {"module": "platform_admin", "status": "ok"}
