from sqlalchemy import Column, String, Integer, JSON
from .database import Base

class IRCode(Base):
    __tablename__ = "ir_codes"

    id   = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    raw  = Column(JSON, nullable=False)   # stores a JSON array of ints
