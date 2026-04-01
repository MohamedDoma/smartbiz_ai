"""
Pydantic schemas for workspace endpoints.
Aligned with 1_database_schema.sql — no slug, no owner_id.
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Requests
# ---------------------------------------------------------------------------

class WorkspaceCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    industry_type: str | None = Field(default=None, max_length=100)
    business_size: str | None = Field(
        default=None,
        max_length=50,
        description="One of: micro, small, medium, enterprise",
    )
class WorkspaceJoinRequest(BaseModel):
    invite_code: str = Field(min_length=1, max_length=50)
    full_name: str = Field(min_length=1, max_length=255)
    phone_number: str = Field(min_length=8, max_length=20)
    password: str = Field(min_length=8, max_length=255)


class WorkspaceApproveRequest(BaseModel):
    role_id: uuid.UUID | None = None
    department_id: uuid.UUID | None = None
    branch_id: uuid.UUID | None = None
    shift_id: uuid.UUID | None = None


# ---------------------------------------------------------------------------
# Responses
# ---------------------------------------------------------------------------

class WorkspaceRead(BaseModel):
    id: uuid.UUID
    name: str
    industry_type: str | None = None
    business_size: str | None = None
    subscription_status: str
    invite_code: str | None = None
    max_users: int
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class WorkspaceJoinResponse(BaseModel):
    success: bool = True
    message: str


class WorkspaceApproveResponse(BaseModel):
    success: bool = True
    message: str
