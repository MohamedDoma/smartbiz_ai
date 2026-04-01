"""
SQLAlchemy models for inventory (warehouses, inventory_levels, inventory_logs).
Aligned with 1_database_schema.sql.
"""

import uuid
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Warehouse(Base):
    __tablename__ = "warehouses"
    __table_args__ = (
        UniqueConstraint("workspace_id", "name", name="uq_warehouses_ws_name"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    workspace_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workspaces.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    branch_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        # FK to branches deferred
        nullable=True,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    location: Mapped[str | None] = mapped_column(Text, nullable=True)


class InventoryLevel(Base):
    __tablename__ = "inventory_levels"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    warehouse_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("warehouses.id", ondelete="CASCADE"),
        nullable=False,
    )
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("products.id", ondelete="CASCADE"),
        nullable=False,
    )
    variant_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        # FK to product_variants deferred
        nullable=True,
    )
    quantity: Mapped[Decimal] = mapped_column(
        Numeric(12, 4), default=Decimal("0.0000"), nullable=False
    )


# Indexes for unique constraints based on variant_id presence
Index(
    "uq_inventory_no_variant",
    InventoryLevel.warehouse_id,
    InventoryLevel.product_id,
    unique=True,
    postgresql_where=InventoryLevel.variant_id.is_(None),
)

Index(
    "uq_inventory_with_variant",
    InventoryLevel.warehouse_id,
    InventoryLevel.product_id,
    InventoryLevel.variant_id,
    unique=True,
    postgresql_where=InventoryLevel.variant_id.is_not(None),
)


class InventoryLog(Base):
    __tablename__ = "inventory_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    workspace_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workspaces.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    warehouse_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("warehouses.id", ondelete="SET NULL"),
        nullable=True,
    )
    product_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("products.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    change_type: Mapped[str] = mapped_column(String(50), nullable=False)
    quantity_changed: Mapped[Decimal] = mapped_column(
        Numeric(12, 4), nullable=False
    )
    new_quantity: Mapped[Decimal] = mapped_column(
        Numeric(12, 4), nullable=False
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )
