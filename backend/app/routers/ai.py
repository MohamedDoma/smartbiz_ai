"""
AI router — intelligent suggestions, forecasting, chat.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/ai", tags=["AI"])


@router.get("/ping")
async def ping():
    """Placeholder health-check for the AI module."""
    return {"module": "ai", "status": "ok"}
