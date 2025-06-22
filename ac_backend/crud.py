from sqlalchemy.orm import Session
from fastapi import HTTPException
from . import models, schemas

def get_all(db: Session):
    return db.query(models.IRCode).all()

def get_by_name(db: Session, name: str):
    return db.query(models.IRCode).filter(models.IRCode.name == name).first()

def create(db: Session, code: schemas.IRCodeCreate):
    if get_by_name(db, code.name):
        raise HTTPException(409, detail="Command already exists")
    db_obj = models.IRCode(name=code.name, raw=code.raw)
    db.add(db_obj)
    db.commit()
    db.refresh(db_obj)
    return db_obj

def delete(db: Session, name: str):
    obj = get_by_name(db, name)
    if not obj:
        raise HTTPException(404, detail="Not found")
    db.delete(obj)
    db.commit()
    return {"status": "deleted"}

def rename(db: Session, old: str, new: str):
    obj = get_by_name(db, old)
    if not obj:
        raise HTTPException(404, detail="Old name not found")
    if get_by_name(db, new):
        raise HTTPException(409, detail="New name already exists")
    obj.name = new
    db.commit()
    db.refresh(obj)
    return obj
