"""Active SQLAlchemy engine/session configuration."""
import uuid
from sqlalchemy import create_engine, event
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.core.database_config import load_database_config

DATABASE_CONFIG = load_database_config()
DATABASE_URL = DATABASE_CONFIG.url

# SQLite needs check_same_thread=False; PostgreSQL does not
connect_args = {"check_same_thread": False} if DATABASE_CONFIG.dialect == "sqlite" else {}

engine = create_engine(DATABASE_URL, connect_args=connect_args)

if DATABASE_CONFIG.dialect == "sqlite":
    @event.listens_for(engine, "connect")
    def _sqlite_uuid_default(dbapi_connection, _connection_record):
        """Emulate PostgreSQL's gen_random_uuid() only for local SQLite."""
        dbapi_connection.create_function("gen_random_uuid", 0, lambda: str(uuid.uuid4()))
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    """FastAPI dependency that yields a DB session and auto-closes it."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
