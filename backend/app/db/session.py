"""
Async SQLAlchemy engine and session factory.
"""

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import get_settings

settings = get_settings()

_is_sqlite = settings.DATABASE_URL.startswith("sqlite")

_engine_kwargs: dict = {
    "echo": settings.DATABASE_ECHO,
}

if not _is_sqlite:
    # Connection-pool tuning only applies to server-based databases.
    _engine_kwargs.update(
        pool_size=20,
        max_overflow=10,
        pool_pre_ping=True,
    )

engine = create_async_engine(settings.DATABASE_URL, **_engine_kwargs)

async_session_factory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)
