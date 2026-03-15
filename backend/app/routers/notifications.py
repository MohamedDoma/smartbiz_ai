"""
Notifications router — list, mark-read, preferences.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/notifications", tags=["Notifications"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the notifications module."""
    return {"module": "notifications", "status": "ok"}
