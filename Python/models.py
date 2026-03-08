from sqlalchemy import Column, Integer, String, DateTime, Boolean, ForeignKey
from sqlalchemy.orm import relationship
from Python.database import Base
from datetime import datetime

class Script(Base):
    __tablename__ = "scripts"

    uid = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True, nullable=False)
    script = Column(String, nullable=False)
    executions = Column(Integer, default=0, nullable=False)

    keys = relationship("Key", back_populates="script_obj", cascade="all, delete")


class Key(Base):
    __tablename__ = "keys"

    key = Column(String, primary_key=True, index=True)
    hashed_key = Column(String, primary_key=True, index=True)
    script_uid = Column(Integer, ForeignKey("scripts.uid"), index=True, nullable=False)
    hwid = Column(String, index=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    claimed_at = Column(DateTime)
    expiresat = Column(DateTime, index=True, nullable=False)
    revoked = Column(Boolean, default=False, nullable=False, index=True)

    script_obj = relationship("Script", back_populates="keys")
    sessions = relationship("Session", back_populates="key_obj", cascade="all, delete")


class Session(Base):
    __tablename__ = "sessions"

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String, unique=True, index=True, nullable=False)
    key_value = Column(String, ForeignKey("keys.key"), nullable=False)

    hwid = Column(String, nullable=False, index=True)
    ip = Column(String, nullable=False)
    expiresat = Column(DateTime, nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    used = Column(Boolean, default=False, nullable=False)

    key_obj = relationship("Key", back_populates="sessions")
