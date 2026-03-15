"""
Accounting router — journal entries, reports, ledger.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/accounting", tags=["Accounting"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the accounting module."""
    return {"module": "accounting", "status": "ok"}
