"""
Pydantic schemas for the Product module.
Mapped to 3_api_contracts.md.
"""

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field


class ProductBase(BaseModel):
    name: str = Field(..., max_length=255)
    base_price: Decimal = Field(..., ge=0, decimal_places=2)
    cost_price: Decimal = Field(default=Decimal("0.00"), ge=0, decimal_places=2)
    sku: str | None = Field(default=None, max_length=100)
    type: Literal["physical", "service", "digital", "subscription"] = "physical"
    category_id: uuid.UUID | None = None
    unit_id: uuid.UUID | None = None
    tax_id: uuid.UUID | None = None
    min_stock_alert: int = Field(default=5, ge=0)
    dynamic_attributes: dict | None = None


class ProductCreate(ProductBase):
    pass


class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=255)
    base_price: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    cost_price: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    sku: str | None = Field(default=None, max_length=100)
    type: Literal["physical", "service", "digital", "subscription"] | None = None
    category_id: uuid.UUID | None = None
    unit_id: uuid.UUID | None = None
    tax_id: uuid.UUID | None = None
    min_stock_alert: int | None = Field(default=None, ge=0)
    dynamic_attributes: dict | None = None


class ProductRead(ProductBase):
    id: uuid.UUID
    workspace_id: uuid.UUID
    is_deleted: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
