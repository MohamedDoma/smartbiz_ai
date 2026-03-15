"""
Auth router — registration, login, token refresh.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/auth", tags=["Auth"])


@router.post("/register")
async def register():
    """Register a new user account."""
    # TODO: implement
    return {"message": "not implemented"}


@router.post("/login")
async def login():
    """Authenticate and return tokens."""
    # TODO: implement
    return {"message": "not implemented"}


@router.post("/refresh")
async def refresh():
    """Refresh access token."""
    # TODO: implement
    return {"message": "not implemented"}
