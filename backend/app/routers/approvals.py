"""
Approvals router — approval workflows, pending items, actions.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/approvals", tags=["Approvals"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the approvals module."""
    return {"module": "approvals", "status": "ok"}
