from fastapi import FastAPI, Depends
from sqlalchemy.orm import Session
from . import models, schemas, crud
from .database import SessionLocal, engine, Base

Base.metadata.create_all(bind=engine)

app = FastAPI()

# Dependency to get DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.post("/devices/", response_model=schemas.ACDeviceOut)
def create_device(device: schemas.ACDeviceCreate, db: Session = Depends(get_db)):
    return crud.create_device(db=db, device=device)

@app.get("/devices/", response_model=list[schemas.ACDeviceOut])
def read_devices(db: Session = Depends(get_db)):
    return crud.get_devices(db)
