from pydantic import BaseModel


class Check1(BaseModel):
    key: str
    hwid:str
    
class Check2(BaseModel):
    key: str
    sig: str

class CreateKey(BaseModel):
    key: str
    mins: int