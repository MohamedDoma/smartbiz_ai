"""
Model registry — import all models so SQLAlchemy metadata is populated.
"""

from app.models.user import User  # noqa: F401
from app.models.workspace import Workspace  # noqa: F401
from app.models.role import Role  # noqa: F401
from app.models.product import Product  # noqa: F401
from app.models.inventory import Warehouse, InventoryLevel, InventoryLog  # noqa: F401
