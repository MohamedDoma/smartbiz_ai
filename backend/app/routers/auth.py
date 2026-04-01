"""
Auth router — registration, login, token refresh.
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_db
from app.schemas.auth import (
    AuthResponse,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
)
from app.services.auth import login_user, refresh_access_token, register_user

router = APIRouter(prefix="/auth", tags=["Auth"])


@router.post(
    "/register",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new user account",
)
async def register(data: RegisterRequest, db: AsyncSession = Depends(get_db)):
    """Create a new account and return access + refresh tokens."""
    return await register_user(db, data)


@router.post(
    "/login",
    response_model=AuthResponse,
    summary="Authenticate and obtain tokens",
)
async def login(data: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Verify credentials and return access + refresh tokens."""
    return await login_user(db, data)


@router.post(
    "/refresh",
    response_model=TokenResponse,
    summary="Refresh access token",
)
async def refresh(data: RefreshRequest):
    """Validate a refresh token and issue a new access token pair."""
    return await refresh_access_token(data)
