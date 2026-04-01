import uuid

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import RequirePermission, get_db
from app.models.user import User
from app.schemas.products import ProductCreate, ProductRead, ProductUpdate
from app.services import products as products_service

router = APIRouter(prefix="/products", tags=["Products"])


@router.post(
    "",
    response_model=ProductRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new product",
)
async def create_product(
    data: ProductCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(RequirePermission("products.create")),
):
    """Create a product in the current workspace."""
    return await products_service.create_product(db, current_user, data)


@router.get(
    "",
    response_model=list[ProductRead],
    status_code=status.HTTP_200_OK,
    summary="List products",
)
async def list_products(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(RequirePermission("products.view")),
):
    """List all active products in the current workspace."""
    return await products_service.list_products(db, current_user)


@router.get(
    "/{product_id}",
    response_model=ProductRead,
    status_code=status.HTTP_200_OK,
    summary="Get product details",
)
async def get_product(
    product_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(RequirePermission("products.view")),
):
    """Get details of a specific product."""
    return await products_service.get_product(db, current_user, product_id)


@router.put(
    "/{product_id}",
    response_model=ProductRead,
    status_code=status.HTTP_200_OK,
    summary="Update a product",
)
async def update_product(
    product_id: uuid.UUID,
    data: ProductUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(RequirePermission("products.update")),
):
    """Update characteristics of an existing product."""
    return await products_service.update_product(
        db, current_user, product_id, data
    )
