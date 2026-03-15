"""
Sync router — external ERP / third-party data synchronization.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/sync", tags=["Sync"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the sync module."""
    return {"module": "sync", "status": "ok"}
