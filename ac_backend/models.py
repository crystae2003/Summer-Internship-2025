from sqlalchemy import Column, String, JSON, DateTime, func, TIMESTAMP
from sqlalchemy.ext.asyncio import AsyncAttrs, create_async_engine, async_sessionmaker
from sqlalchemy.orm import declarative_base

Base = declarative_base()

from sqlalchemy.dialects.postgresql import JSONB

class Command(Base):
    __tablename__ = "commands"
    name = Column(String, primary_key=True)
    raw_timings = Column(JSONB, nullable=False)
    learned_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
