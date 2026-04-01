"""
Workspaces router — create, list workspaces.
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_current_user, get_db, RequirePermission
from app.models.user import User
from app.schemas.workspaces import (
    WorkspaceApproveRequest,
    WorkspaceApproveResponse,
    WorkspaceCreate,
    WorkspaceJoinRequest,
    WorkspaceJoinResponse,
    WorkspaceRead,
)
from app.services.workspaces import (
    approve_join_request,
    create_workspace,
    join_workspace,
    list_user_workspaces,
)

router = APIRouter(prefix="/workspaces", tags=["Workspaces"])


@router.post(
    "",
    response_model=WorkspaceRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new workspace",
)
async def create(
    data: WorkspaceCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a workspace and assign the authenticated user as owner."""
    return await create_workspace(db, current_user, data)


@router.get(
    "",
    response_model=list[WorkspaceRead],
    summary="List workspaces for current user",
)
async def list_workspaces(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return await list_user_workspaces(db, current_user.id)


@router.post(
    "/join",
    response_model=WorkspaceJoinResponse,
    status_code=status.HTTP_200_OK,
    summary="Submit a request to join a workspace",
)
async def request_to_join(
    data: WorkspaceJoinRequest,
    db: AsyncSession = Depends(get_db),
):
    """Public endpoint to join a workspace by invite code."""
    return await join_workspace(db, data)


@router.post(
    "/join/{request_id}/approve",
    response_model=WorkspaceApproveResponse,
    status_code=status.HTTP_200_OK,
    summary="Approve a pending join request",
)
async def approve_join(
    request_id: str,
    data: WorkspaceApproveRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(RequirePermission("users.approve")),
):
    """Approve a pending user to join your workspace."""
    # Convert string to UUID to match service signature
    import uuid
    try:
        req_uuid = uuid.UUID(request_id)
    except ValueError:
        from fastapi import HTTPException
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Invalid request_id format (must be UUID)",
        )

    return await approve_join_request(db, current_user, req_uuid, data)
