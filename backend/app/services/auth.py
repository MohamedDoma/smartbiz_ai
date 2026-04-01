"""
Auth service — register, login, refresh.
Aligned with 1_database_schema.sql — phone_number auth, password_hash column.
"""

import uuid

from fastapi import HTTPException, status
from jose import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)
from app.models.user import User
from app.schemas.auth import (
    AuthResponse,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserRead,
)


async def register_user(db: AsyncSession, data: RegisterRequest) -> AuthResponse:
    """Create a new user account and return tokens.

    Registration creates a user without a workspace (workspace_id=None).
    The user gets assigned to a workspace when they create or join one.
    New users start with approval_status='pending' and is_active=False
    when joining an existing workspace, but for self-registration
    (no workspace yet) we set approval_status='approved' and is_active=True.
    """
    # Check if phone_number already taken (global check for users without workspace)
    stmt = select(User).where(User.phone_number == data.phone_number)
    result = await db.execute(stmt)
    if result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A user with this phone number already exists.",
        )

    user = User(
        id=uuid.uuid4(),
        phone_number=data.phone_number,
        full_name=data.full_name,
        password_hash=hash_password(data.password),
        # Self-registered users are immediately active (no workspace to approve them)
        approval_status="approved",
        is_active=True,
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)

    token_payload = {"sub": str(user.id)}
    access_token = create_access_token(token_payload)
    refresh_token = create_refresh_token(token_payload)

    return AuthResponse(
        user=UserRead.model_validate(user),
        access_token=access_token,
        refresh_token=refresh_token,
    )


async def login_user(db: AsyncSession, data: LoginRequest) -> AuthResponse:
    """Authenticate a user by phone_number and return tokens."""
    stmt = select(User).where(User.phone_number == data.phone_number)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid phone number or password.",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is not active. Awaiting approval.",
        )

    token_payload = {"sub": str(user.id)}
    access_token = create_access_token(token_payload)
    refresh_token = create_refresh_token(token_payload)

    return AuthResponse(
        user=UserRead.model_validate(user),
        access_token=access_token,
        refresh_token=refresh_token,
    )


async def refresh_access_token(data: RefreshRequest) -> TokenResponse:
    """Validate a refresh token and issue a new access token."""
    try:
        payload = decode_token(data.refresh_token)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token.",
        )

    if payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token is not a refresh token.",
        )

    sub = payload.get("sub")
    if not sub:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload.",
        )

    new_access = create_access_token({"sub": sub})
    new_refresh = create_refresh_token({"sub": sub})

    return TokenResponse(access_token=new_access, refresh_token=new_refresh)
