"""
FastAPI dependency injection: database sessions, auth, workspace context.
"""

from typing import AsyncGenerator

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import async_session_factory


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Yield a database session per request."""
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def get_current_user():
    """Placeholder: extract and validate current user from JWT."""
    # TODO: implement JWT extraction from Authorization header
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not implemented")


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
