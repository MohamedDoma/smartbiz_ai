"""
Invoices router — generate, list, download invoices.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/invoices", tags=["Invoices"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the invoices module."""
    return {"module": "invoices", "status": "ok"}
