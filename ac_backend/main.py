from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from . import models, schemas, crud
from .database import engine, SessionLocal, Base

# Create tables
Base.metadata.create_all(bind=engine)

app = FastAPI(title="IR Code Service")

# Dependency to get DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.post("/learn", response_model=schemas.IRCode)
def learn(code: schemas.IRCodeCreate, db: Session = Depends(get_db)):
    """Store a new IR code."""
    return crud.create(db, code)

@app.get("/list", response_model=List[schemas.IRCode])
def list_codes(db: Session = Depends(get_db)):
    """Return all codes."""
    return crud.get_all(db)

@app.get("/send")
def send(name: str, db: Session = Depends(get_db)):
    """Fetch one code’s raw array."""
    obj = crud.get_by_name(db, name)
    if not obj:
        raise HTTPException(404, detail="Not found")
    return {"name": obj.name, "raw": obj.raw}

@app.delete("/delete")
def delete(name: str, db: Session = Depends(get_db)):
    """Delete a code."""
    return crud.delete(db, name)
@app.get("/delete")
def delete_command_get(name: str, db: Session = Depends(get_db)):
    return delete_command(name, db)


@app.put("/rename", response_model=schemas.IRCode)
def rename(old: str, new: str, db: Session = Depends(get_db)):
    """Rename a code."""
    return crud.rename(db, old, new)
@app.get("/rename")
def rename_command_get(old: str, new: str, db: Session = Depends(get_db)):
    # simply call the existing logic
    return rename_command(RenamePayload(old=old, new=new), db)