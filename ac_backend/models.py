from sqlalchemy import Column, Integer, String, Boolean
from .database import Base

class ACDevice(Base):
    __tablename__ = "ac_devices"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    status = Column(Boolean, default=False)  # False = off, True = on
