"""
FastAPI dependency injection: database sessions, auth, workspace context.
"""

import uuid
from typing import AsyncGenerator

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import decode_token
from app.db.session import async_session_factory
from app.models.role import Role
from app.models.user import User

settings = get_settings()

oauth2_scheme = OAuth2PasswordBearer(
    tokenUrl=f"{settings.API_V1_PREFIX}/auth/login",
    auto_error=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Yield a database session per request."""
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def get_current_user(
    token: str | None = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Extract and validate current user from JWT Bearer token."""
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        payload = decode_token(token)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token is not an access token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    sub = payload.get("sub")
    if not sub:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        user_uuid = uuid.UUID(sub)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    stmt = select(User).where(User.id == user_uuid)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or deactivated.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user


async def get_workspace_id(
    x_workspace_id: str | None = Header(None, alias="X-Workspace-ID"),
) -> str:
    """Extract workspace ID from request header."""
    if not x_workspace_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="X-Workspace-ID header required",
        )
    return x_workspace_id


async def set_workspace_context(
    db: AsyncSession = Depends(get_db),
    workspace_id: str = Depends(get_workspace_id),
) -> AsyncSession:
    """Set PostgreSQL session variable for RLS enforcement."""
    await db.execute(
        f"SET app.workspace_id = '{workspace_id}'"  # noqa: S608
    )
    return db


async def require_workspace_member(
    current_user: User = Depends(get_current_user),
    workspace_id: str | None = Header(None, alias="X-Workspace-ID"),
) -> User:
    """Ensure the user is a member of the requested workspace."""
    if not workspace_id:
        if not current_user.workspace_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="User does not belong to any workspace",
            )
        return current_user

    # Compare explicit header against user's attached workspace
    if str(current_user.workspace_id) != workspace_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User does not belong to the requested workspace",
        )
    return current_user


class RequirePermission:
    """Dependency class to check if a user has a specific permission.
    
    Checks in this order:
    1. User's personal permissions override (JSON)
    2. User's assigned Role permissions (JSON)
    
    If the capability is missing or false, raises 403 Forbidden.
    """
    def __init__(self, required_permission: str):
        self.required_permission = required_permission

    async def __call__(
        self,
        current_user: User = Depends(require_workspace_member),
        db: AsyncSession = Depends(get_db),
    ) -> User:
        # 1. Check user-level override first
        user_perms = current_user.permissions or {}
        if self.required_permission in user_perms:
            if user_perms.get(self.required_permission) is True:
                return current_user
            else:
                # Explicitly denied
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Permission denied: {self.required_permission}",
                )

        # 2. Check role-level permissions
        if not current_user.role_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"No role assigned. Permission denied: {self.required_permission}",
            )

        stmt = select(Role).where(Role.id == current_user.role_id)
        result = await db.execute(stmt)
        role = result.scalar_one_or_none()

        if not role:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Assigned role not found",
            )

        role_perms = role.permissions or {}
        if role_perms.get(self.required_permission) is not True:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Permission denied: {self.required_permission}",
            )

        return current_user
