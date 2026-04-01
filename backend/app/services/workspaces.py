"""
Workspace service — create workspace, list user workspaces.
Aligned with 1_database_schema.sql — no memberships, no slug.
Users belong to a workspace via users.workspace_id.
"""

import secrets
import uuid

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password
from app.models.user import User
from app.models.workspace import Workspace
from app.schemas.workspaces import (
    WorkspaceApproveRequest,
    WorkspaceApproveResponse,
    WorkspaceCreate,
    WorkspaceJoinRequest,
    WorkspaceJoinResponse,
    WorkspaceRead,
)
from app.services.roles import seed_default_roles


def _generate_invite_code() -> str:
    """Generate a random 8-character uppercase invite code."""
    return secrets.token_hex(4).upper()  # 8 hex chars


async def create_workspace(
    db: AsyncSession,
    current_user: User,
    data: WorkspaceCreate,
) -> WorkspaceRead:
    """Create a workspace and assign the creator to it.

    Sets the current user's workspace_id to the new workspace.
    """
    # Validate business_size if provided
    valid_sizes = {"micro", "small", "medium", "enterprise"}
    if data.business_size and data.business_size not in valid_sizes:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"business_size must be one of: {', '.join(sorted(valid_sizes))}",
        )

    # Generate a unique invite_code
    invite_code = _generate_invite_code()
    while True:
        stmt = select(Workspace).where(Workspace.invite_code == invite_code)
        result = await db.execute(stmt)
        if result.scalar_one_or_none() is None:
            break
        invite_code = _generate_invite_code()

    workspace = Workspace(
        id=uuid.uuid4(),
        name=data.name,
        industry_type=data.industry_type,
        business_size=data.business_size,
        invite_code=invite_code,
    )
    db.add(workspace)
    await db.flush()

    # Seed roles and assign the creator "Owner"
    roles_map = await seed_default_roles(db, workspace.id)
    owner_role_id = roles_map.get("Owner")

    current_user.workspace_id = workspace.id
    current_user.role_id = owner_role_id
    current_user.permissions = None  # Clear any prior overriding privileges

    await db.flush()
    await db.refresh(workspace)

    return WorkspaceRead.model_validate(workspace)


async def list_user_workspaces(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> list[WorkspaceRead]:
    """Return the workspace(s) a user belongs to.

    In the current schema, a user belongs to at most one workspace
    via users.workspace_id.
    """
    stmt = (
        select(Workspace)
        .join(User, User.workspace_id == Workspace.id)
        .where(User.id == user_id)
        .order_by(Workspace.created_at.desc())
    )
    result = await db.execute(stmt)
    workspaces = result.scalars().all()
    return [WorkspaceRead.model_validate(ws) for ws in workspaces]


async def join_workspace(
    db: AsyncSession,
    data: WorkspaceJoinRequest,
) -> WorkspaceJoinResponse:
    """Submit a request to join a workspace using an invite code."""
    # 1. Find the workspace
    stmt = select(Workspace).where(
        Workspace.invite_code == data.invite_code.upper(),
        Workspace.is_active == True,
    )
    result = await db.execute(stmt)
    workspace = result.scalar_one_or_none()

    if not workspace:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Valid active workspace not found for this invite code",
        )

    # 2. Check if user with phone number already exists
    stmt_user = select(User).where(User.phone_number == data.phone_number)
    user_exists = (await db.execute(stmt_user)).scalar_one_or_none()
    if user_exists:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this phone number already exists",
        )

    # 3. Create the pending user
    new_user = User(
        id=uuid.uuid4(),
        workspace_id=workspace.id,
        phone_number=data.phone_number,
        full_name=data.full_name,
        password_hash=hash_password(data.password),
        approval_status="pending",
        is_active=False,
    )
    db.add(new_user)
    await db.flush()

    return WorkspaceJoinResponse(
        success=True,
        message="Join request submitted. Awaiting approval.",
    )


async def approve_join_request(
    db: AsyncSession,
    current_user: User,
    request_id: uuid.UUID,
    data: WorkspaceApproveRequest,
) -> WorkspaceApproveResponse:
    """Approve a pending join request (the pending user record)."""
    # 1. Lookup the target user (request_id points to the user id)
    stmt = select(User).where(User.id == request_id)
    result = await db.execute(stmt)
    target_user = result.scalar_one_or_none()

    if not target_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Join request (user) not found",
        )

    # 2. Validate workspace context
    if target_user.workspace_id != current_user.workspace_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to approve requests for this workspace",
        )

    # 3. Check authorization (approver must be active)
    if not current_user.is_active or current_user.approval_status != "approved":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You must be an active, approved user to approve others",
        )

    # 4. Check status
    if target_user.approval_status != "pending":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"User is already {target_user.approval_status}",
        )

    # 5. Update user properties
    target_user.role_id = data.role_id
    target_user.department_id = data.department_id
    target_user.branch_id = data.branch_id
    target_user.shift_id = data.shift_id
    target_user.approval_status = "approved"
    target_user.is_active = True

    await db.flush()

    return WorkspaceApproveResponse(
        success=True,
        message="User approved and activated.",
    )
