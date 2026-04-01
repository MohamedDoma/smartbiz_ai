import uuid

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.product import Product
from app.models.user import User
from app.schemas.products import ProductCreate, ProductRead, ProductUpdate


async def create_product(
    db: AsyncSession, current_user: User, data: ProductCreate
) -> ProductRead:
    # Verify SKU uniqueness within workspace if provided
    if data.sku:
        stmt = select(Product).where(
            Product.workspace_id == current_user.workspace_id,
            Product.sku == data.sku,
            Product.is_deleted == False,
        )
        existing = await db.execute(stmt)
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A product with this SKU already exists in this workspace",
            )

    product = Product(
        workspace_id=current_user.workspace_id,
        **data.model_dump(),
    )
    db.add(product)
    await db.flush()
    await db.refresh(product)
    return ProductRead.model_validate(product)


async def list_products(
    db: AsyncSession, current_user: User
) -> list[ProductRead]:
    stmt = select(Product).where(
        Product.workspace_id == current_user.workspace_id,
        Product.is_deleted == False,
    )
    result = await db.execute(stmt)
    products = result.scalars().all()
    return [ProductRead.model_validate(p) for p in products]


async def get_product(
    db: AsyncSession, current_user: User, product_id: uuid.UUID
) -> ProductRead:
    stmt = select(Product).where(
        Product.id == product_id,
        Product.workspace_id == current_user.workspace_id,
        Product.is_deleted == False,
    )
    result = await db.execute(stmt)
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Product not found"
        )
    return ProductRead.model_validate(product)


async def update_product(
    db: AsyncSession,
    current_user: User,
    product_id: uuid.UUID,
    data: ProductUpdate,
) -> ProductRead:
    stmt = select(Product).where(
        Product.id == product_id,
        Product.workspace_id == current_user.workspace_id,
        Product.is_deleted == False,
    )
    result = await db.execute(stmt)
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Product not found"
        )

    # Re-verify SKU uniqueness if SKU is being updated
    if data.sku and data.sku != product.sku:
        sku_stmt = select(Product).where(
            Product.workspace_id == current_user.workspace_id,
            Product.sku == data.sku,
            Product.is_deleted == False,
            Product.id != product_id,
        )
        existing = await db.execute(sku_stmt)
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A product with this SKU already exists in this workspace",
            )

    update_data = data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(product, key, value)

    await db.flush()
    await db.refresh(product)
    return ProductRead.model_validate(product)
