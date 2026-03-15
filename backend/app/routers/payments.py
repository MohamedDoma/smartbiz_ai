"""
Payments router — record and list payments.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/payments", tags=["Payments"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the payments module."""
    return {"module": "payments", "status": "ok"}
