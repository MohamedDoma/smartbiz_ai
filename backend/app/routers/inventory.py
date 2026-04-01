from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import RequirePermission, get_db
from app.models.user import User
from app.schemas.inventory import (
    InventoryAdjustRequest,
    InventoryLevelRead,
    InventoryLogRead,
)
from app.services import inventory as inventory_service

router = APIRouter(prefix="/inventory", tags=["Inventory"])


@router.post(
    "/adjust",
    response_model=InventoryLevelRead,
    status_code=status.HTTP_200_OK,
    summary="Adjust inventory stock level manually",
)
async def adjust_inventory(
    data: InventoryAdjustRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(RequirePermission("inventory.adjust")),
):
    """
    Manually adjust the stock of a product in a warehouse.
    This safely creates a transactional InventoryLevel entry and an Audit Log.
    """
    return await inventory_service.adjust_inventory(db, current_user, data)


@router.get(
    "",
    response_model=list[InventoryLevelRead],
    status_code=status.HTTP_200_OK,
    summary="List total inventory levels globally",
)
async def list_inventory(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(RequirePermission("inventory.view")),
):
    """Retrieve all stock levels inside the current users workspace."""
    return await inventory_service.list_inventory(db, current_user)


@router.get(
    "/movements",
    response_model=list[InventoryLogRead],
    status_code=status.HTTP_200_OK,
    summary="Get recent inventory movements / logs audit trail",
)
async def get_inventory_movements(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(RequirePermission("inventory.view_logs")),
):
    """Fetch history from inventory_logs directly based on workspace context."""
    return await inventory_service.get_inventory_movements(db, current_user)
