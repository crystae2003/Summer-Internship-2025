from sqlalchemy.orm import Session
from . import models, schemas

def create_device(db: Session, device: schemas.ACDeviceCreate):
    db_device = models.ACDevice(name=device.name)
    db.add(db_device)
    db.commit()
    db.refresh(db_device)
    return db_device

def get_devices(db: Session):
    return db.query(models.ACDevice).all()
