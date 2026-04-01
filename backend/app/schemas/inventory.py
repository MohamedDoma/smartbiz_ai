"""
Pydantic schemas for the Inventory module.
Mapped to 3_api_contracts.md.
"""

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field


class InventoryAdjustRequest(BaseModel):
    product_id: uuid.UUID
    warehouse_id: uuid.UUID
    variant_id: uuid.UUID | None = None
    change_type: str = Field(..., max_length=50)  # e.g., "manual_adjustment"
    quantity_changed: Decimal = Field(..., decimal_places=4)
    notes: str | None = None


class InventoryLevelRead(BaseModel):
    id: uuid.UUID
    warehouse_id: uuid.UUID
    product_id: uuid.UUID
    variant_id: uuid.UUID | None
    quantity: Decimal

    class Config:
        from_attributes = True


class InventoryLogRead(BaseModel):
    id: uuid.UUID
    workspace_id: uuid.UUID
    warehouse_id: uuid.UUID | None
    product_id: uuid.UUID
    user_id: uuid.UUID | None
    change_type: str
    quantity_changed: Decimal
    new_quantity: Decimal
    notes: str | None
    created_at: datetime

    class Config:
        from_attributes = True
