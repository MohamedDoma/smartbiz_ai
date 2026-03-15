"""
Users router — profile, list, role management.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/users", tags=["Users"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the users module."""
    return {"module": "users", "status": "ok"}
