"""
Inventory router — stock levels, adjustments, transfers.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/inventory", tags=["Inventory"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the inventory module."""
    return {"module": "inventory", "status": "ok"}
