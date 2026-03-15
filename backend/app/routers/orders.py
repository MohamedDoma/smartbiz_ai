"""
Orders router — create, list, update, cancel orders.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/orders", tags=["Orders"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the orders module."""
    return {"module": "orders", "status": "ok"}
