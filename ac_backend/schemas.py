from pydantic import BaseModel

class ACDeviceBase(BaseModel):
    name: str

class ACDeviceCreate(ACDeviceBase):
    pass

class ACDeviceOut(ACDeviceBase):
    id: int
    status: bool

    class Config:
        orm_mode = True
