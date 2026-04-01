"""
User model — matches 1_database_schema.sql `users` table.

Users belong to a single workspace via workspace_id.
Authentication is phone_number + password_hash (no email).
New users start with approval_status='pending' and is_active=FALSE.
"""

import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    Numeric,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class User(Base):
    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("workspace_id", "phone_number", name="uq_users_ws_phone"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    workspace_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workspaces.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    department_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        # FK to departments — deferred until departments model exists
        nullable=True,
    )
    manager_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    shift_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        # FK to shifts — will reference when shifts model exists
        nullable=True,
    )
    branch_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        # FK to branches — will reference when branches model exists
        nullable=True,
    )
    role_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        # FK to roles — will reference when roles model exists
        nullable=True,
    )
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    phone_number: Mapped[str] = mapped_column(String(20), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    permissions: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    hire_date: Mapped[date | None] = mapped_column(
        Date, default=date.today
    )
    base_salary: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), default=Decimal("0.00")
    )
    annual_leave_balance: Mapped[int] = mapped_column(Integer, default=21)
    approval_status: Mapped[str] = mapped_column(
        String(50), default="pending"
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
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)
