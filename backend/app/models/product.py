"""
SQLAlchemy model for products.
Aligned with 1_database_schema.sql.
"""

import uuid
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import (
    Boolean,
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


class Product(Base):
    __tablename__ = "products"
    __table_args__ = (
        UniqueConstraint("workspace_id", "sku", name="uq_products_ws_sku"),
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
    category_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        # FK to product_categories deferred
        nullable=True,
    )
    type: Mapped[str] = mapped_column(
        String(50), default="physical", nullable=False
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    sku: Mapped[str | None] = mapped_column(String(100), nullable=True)
    unit_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        # FK to units_of_measure deferred
        nullable=True,
    )
    base_price: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), nullable=False
    )
    cost_price: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), default=Decimal("0.00"), nullable=False
    )
    tax_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        # FK to taxes deferred
        nullable=True,
    )
    min_stock_alert: Mapped[int] = mapped_column(Integer, default=5)
    dynamic_attributes: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
