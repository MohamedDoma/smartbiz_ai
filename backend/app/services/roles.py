import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.role import Role


async def seed_default_roles(
    db: AsyncSession, workspace_id: uuid.UUID
) -> dict[str, uuid.UUID]:
    """
    Seed default workspace roles and their permissions for a new workspace.
    Returns a dictionary mapping role names to their new UUIDs.
    """
    # Define exact permissions based on 7_roles_permissions_matrix.md
    
    # Base permissions every standard user might need (Viewers only get read access)
    base_employee_perms = {
        "schedule.view": True,
        "leave.request": True,
        "profile.update": True,
        "tasks.view": True,
    }
    
    roles_data = [
        {
            "name": "Owner",
            "permissions": {
                "ownership.transfer": True,
                "workspace.delete": True,
                "ai.approve_critical": True,
                "subscription.manage": True,
                "co_owners.manage": True,
                "admins.manage": True,
                "modules.manage": True,
                "workspace.settings": True,
                "users.approve": True,
                "reports.view": True,
                "ai.configure": True,
                "products.view": True,
                "products.create": True,
                "products.update": True,
                "inventory.view": True,
                "inventory.adjust": True,
                "inventory.view_logs": True,
            },
        },
        {
            "name": "Co-owner",
            "permissions": {
                "admins.manage": True,
                "departments.manage": True,
                "users.manage": True,
                "ai.approve": True,
                "workspace.settings": True,
                "modules.manage": True,
                "operations.approve": True,
                "users.approve": True,
                "products.view": True,
                "products.create": True,
                "products.update": True,
                "inventory.view": True,
                "inventory.adjust": True,
                "inventory.view_logs": True,
            },
        },
        {
            "name": "Admin",
            "permissions": {
                "users.manage": True,
                "roles.manage": True,
                "branches.manage": True,
                "departments.manage": True,
                "users.approve": True,
                "inventory.manage": True,
                "orders.manage": True,
                "invoices.manage": True,
                "payments.manage": True,
                "contacts.manage": True,
                "products.view": True,
                "products.create": True,
                "products.update": True,
                "inventory.view": True,
                "inventory.adjust": True,
                "inventory.view_logs": True,
            },
        },
        {
            "name": "Department Head",
            "permissions": {
                "users.approve": True,  # For their dept
                "team.manage": True,
                "tasks.assign": True,
                "reports.dept_view": True,
                "leave.approve": True,
            },
        },
        {
            "name": "HR",
            "permissions": {
                "users.approve": True,
                "employees.manage": True,
                "shifts.manage": True,
                "attendance.manage": True,
                "leave.manage": True,
                "payroll.manage": True,
            },
        },
        {
            "name": "Accountant",
            "permissions": {
                "reports.financial_view": True,
                "accounts.manage": True,
                "journal.create": True,
                "payments.record": True,
                "expenses.manage": True,
                "invoices.manage": True,
                "taxes.manage": True,
            },
        },
        {
            "name": "Sales",
            "permissions": {
                "contacts.manage": True,
                "orders.create": True,
                "invoices.create": True,
                "customers.view_history": True,
                "reports.sales_view": True,
                "products.view": True,
            },
        },
        {
            "name": "Warehouse Staff",
            "permissions": {
                "products.view": True,
                "inventory.view": True,
                "inventory.adjust": True,
                "inventory.transfer": True,
                "inventory.manage": True,
                "inventory.view_logs": True,
            },
        },
        {
            "name": "Cashier",
            "permissions": {
                "pos.create_sale": True,
                "payments.process": True,
                "receipts.print": True,
                "products.view": True,
                "sales.basic_history": True,
            },
        },
        {
            "name": "Employee",
            "permissions": base_employee_perms,
        },
        {
            "name": "Viewer",
            "permissions": {
                "dashboards.view": True,
                "reports.view": True,
                "analytics.view": True,
            },
        },
    ]

    roles_map = {}
    
    for rd in roles_data:
        role_record = Role(
            id=uuid.uuid4(),
            workspace_id=workspace_id,
            name=rd["name"],
            permissions=rd["permissions"],
        )
        db.add(role_record)
        roles_map[rd["name"]] = role_record.id

    await db.flush()
    return roles_map
