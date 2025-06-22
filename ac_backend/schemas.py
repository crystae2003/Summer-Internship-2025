from pydantic import BaseModel
from typing import List

class IRCodeBase(BaseModel):
    name: str
    raw: List[int]

class IRCodeCreate(IRCodeBase):
    pass

class IRCode(IRCodeBase):
    id: int

    class Config:
        orm_mode = True
