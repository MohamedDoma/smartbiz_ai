"""
SmartBiz AI — FastAPI Application Entry Point
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.routers import (
    accounting,
    ai,
    approvals,
    auth,
    inventory,
    invoices,
    notifications,
    orders,
    payments,
    platform_admin,
    products,
    sync,
    users,
    workspaces,
)

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events."""
    # TODO: verify database connection on startup
    # TODO: initialize Redis connection pool
    yield
    # TODO: cleanup connections on shutdown


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    lifespan=lifespan,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Health check
@app.get("/health")
async def health():
    return {"status": "ok", "version": settings.APP_VERSION}


# --- Router Registration -------------------------------------------------
_routers = [
    auth,
    workspaces,
    users,
    products,
    inventory,
    orders,
    invoices,
    payments,
    accounting,
    ai,
    notifications,
    approvals,
    sync,
    platform_admin,
]

for _mod in _routers:
    app.include_router(_mod.router, prefix=settings.API_V1_PREFIX)
