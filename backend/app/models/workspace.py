"""
Workspace model — matches 1_database_schema.sql `workspaces` table.

No slug, no owner_id, no WorkspaceMembership.
Users belong to a workspace via users.workspace_id.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, Integer, JSON, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Workspace(Base):
    __tablename__ = "workspaces"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    industry_type: Mapped[str | None] = mapped_column(
        String(100), nullable=True
    )
    business_size: Mapped[str | None] = mapped_column(
        String(50), nullable=True
    )
    onboarding_data: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    invite_code: Mapped[str | None] = mapped_column(
        String(50), unique=True, nullable=True
    )
    ui_configuration: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    subscription_status: Mapped[str] = mapped_column(
        String(50), default="freemium"
    )
    max_users: Mapped[int] = mapped_column(Integer, default=1)
    subscription_end_date: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
