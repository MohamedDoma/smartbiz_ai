import uuid
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.inventory import InventoryLevel, InventoryLog, Warehouse
from app.models.product import Product
from app.models.user import User
from app.schemas.inventory import (
    InventoryAdjustRequest,
    InventoryLevelRead,
    InventoryLogRead,
)


async def adjust_inventory(
    db: AsyncSession, current_user: User, data: InventoryAdjustRequest
) -> InventoryLevelRead:
    # 1. Validate Warehouse exists and belongs to the workspace
    wh_stmt = select(Warehouse).where(
        Warehouse.id == data.warehouse_id,
        Warehouse.workspace_id == current_user.workspace_id,
    )
    if not (await db.execute(wh_stmt)).scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Warehouse not found"
        )

    # 2. Validate Product exists and belongs to the workspace
    pr_stmt = select(Product).where(
        Product.id == data.product_id,
        Product.workspace_id == current_user.workspace_id,
        Product.is_deleted == False,
    )
    if not (await db.execute(pr_stmt)).scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Product not found"
        )

    # 3. Fetch or Create Inventory Level
    level_stmt = select(InventoryLevel).where(
        InventoryLevel.warehouse_id == data.warehouse_id,
        InventoryLevel.product_id == data.product_id,
        InventoryLevel.variant_id == data.variant_id,
    )
    level = (await db.execute(level_stmt)).scalar_one_or_none()

    old_quantity = Decimal("0.0000")
    if level:
        old_quantity = level.quantity
        level.quantity += data.quantity_changed
    else:
        # Prevent creating a record with negative inventory initially
        if data.quantity_changed < 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Insufficient stock for adjustment",
            )
        level = InventoryLevel(
            warehouse_id=data.warehouse_id,
            product_id=data.product_id,
            variant_id=data.variant_id,
            quantity=data.quantity_changed,
        )
        db.add(level)

    # Optional: Prevent negative stock based on business rules
    if level.quantity < 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Adjustment would result in negative stock",
        )

    await db.flush()

    # 4. Insert Audit Log
    log = InventoryLog(
        workspace_id=current_user.workspace_id,
        warehouse_id=data.warehouse_id,
        product_id=data.product_id,
        user_id=current_user.id,
        change_type=data.change_type,
        quantity_changed=data.quantity_changed,
        new_quantity=level.quantity,
        notes=data.notes,
    )
    db.add(log)
    await db.flush()
    await db.refresh(level)

    return InventoryLevelRead.model_validate(level)


async def list_inventory(
    db: AsyncSession, current_user: User
) -> list[InventoryLevelRead]:
    """List all inventory levels globally for the workspace."""
    stmt = (
        select(InventoryLevel)
        .join(Warehouse, InventoryLevel.warehouse_id == Warehouse.id)
        .where(Warehouse.workspace_id == current_user.workspace_id)
    )
    result = await db.execute(stmt)
    levels = result.scalars().all()
    return [InventoryLevelRead.model_validate(lvl) for lvl in levels]


async def get_inventory_movements(
    db: AsyncSession, current_user: User
) -> list[InventoryLogRead]:
    """Fetch history from inventory_logs directly based on workspace context."""
    stmt = (
        select(InventoryLog)
        .where(InventoryLog.workspace_id == current_user.workspace_id)
        .order_by(InventoryLog.created_at.desc())
    )
    result = await db.execute(stmt)
    logs = result.scalars().all()
    return [InventoryLogRead.model_validate(log) for log in logs]
