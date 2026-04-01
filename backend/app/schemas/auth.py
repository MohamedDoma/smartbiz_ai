"""
Pydantic schemas for authentication endpoints.
Aligned with 1_database_schema.sql — uses phone_number (no email on users).
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Requests
# ---------------------------------------------------------------------------

class RegisterRequest(BaseModel):
    phone_number: str = Field(min_length=1, max_length=20)
    password: str = Field(min_length=8, max_length=128)
    full_name: str = Field(min_length=1, max_length=255)


class LoginRequest(BaseModel):
    phone_number: str = Field(min_length=1, max_length=20)
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


# ---------------------------------------------------------------------------
# Responses
# ---------------------------------------------------------------------------

class UserRead(BaseModel):
    id: uuid.UUID
    full_name: str
    phone_number: str
    workspace_id: uuid.UUID | None = None
    approval_status: str
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class AuthResponse(BaseModel):
    user: UserRead
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
