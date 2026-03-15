"""
Products router — CRUD for product catalogue.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/products", tags=["Products"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the products module."""
    return {"module": "products", "status": "ok"}
