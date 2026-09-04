import os
from datetime import datetime
from sqlalchemy import (
    Column,
    String,
    Boolean,
    Float,
    Integer,
    DateTime,
    ForeignKey,
    Text,
    create_engine,
    Index,
)
from sqlalchemy.orm import declarative_base, sessionmaker, relationship

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./data/arcdash.db")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {},
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id = Column(String(64), primary_key=True, index=True)
    username = Column(String(64), unique=True, index=True, nullable=False)
    email = Column(String(128), unique=True, index=True, nullable=True)
    password_hash = Column(String(255), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    last_login = Column(DateTime, default=datetime.utcnow)

    bikes = relationship("Bike", back_populates="user", cascade="all, delete-orphan")
    tuning_profiles = relationship(
        "TuningProfileModel", back_populates="user", cascade="all, delete-orphan"
    )
    rides = relationship("RideModel", back_populates="user", cascade="all, delete-orphan")
    map_favorites = relationship(
        "MapFavoriteModel", back_populates="user", cascade="all, delete-orphan"
    )
    range_calibrations = relationship(
        "RangeCalibrationModel", back_populates="user", cascade="all, delete-orphan"
    )


class Bike(Base):
    __tablename__ = "bikes"

    id = Column(String(64), primary_key=True, index=True)  # Client generated UUID/ID
    user_id = Column(String(64), ForeignKey("users.id"), nullable=False, index=True)
    name = Column(String(128), nullable=False)
    controller_id = Column(String(128), default="")
    controller_name = Column(String(128), default="FarDriver Controller")
    bms_id = Column(String(128), default="")
    bms_name = Column(String(128), default="ANT BMS")
    is_auto_connect = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, index=True)
    deleted_at = Column(DateTime, nullable=True, index=True)

    user = relationship("User", back_populates="bikes")


class TuningProfileModel(Base):
    __tablename__ = "tuning_profiles"

    id = Column(String(64), primary_key=True, index=True)
    user_id = Column(String(64), ForeignKey("users.id"), nullable=False, index=True)
    name = Column(String(128), nullable=False)
    is_stock = Column(Boolean, default=False)
    max_speed_kph = Column(Float, default=45.0)
    max_line_curr_a = Column(Float, default=80.0)
    max_phase_curr_a = Column(Float, default=200.0)
    throttle_response = Column(Integer, default=1)
    boost_seconds = Column(Integer, default=10)
    power_curve_json = Column(Text, default="[]")
    regen_curve_json = Column(Text, default="[]")
    pin_mapping_json = Column(Text, default="{}")
    
    # Community features ready
    is_public = Column(Boolean, default=False, index=True)
    version = Column(Integer, default=1)
    description = Column(String(500), nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, index=True)
    deleted_at = Column(DateTime, nullable=True, index=True)

    user = relationship("User", back_populates="tuning_profiles")


class RideModel(Base):
    __tablename__ = "rides"

    id = Column(String(64), primary_key=True, index=True)
    user_id = Column(String(64), ForeignKey("users.id"), nullable=False, index=True)
    bike_id = Column(String(64), nullable=True, index=True)
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime, nullable=False)
    duration_sec = Column(Integer, default=0)
    distance_km = Column(Float, default=0.0)
    avg_speed_kph = Column(Float, default=0.0)
    max_speed_kph = Column(Float, default=0.0)
    energy_used_wh = Column(Float, default=0.0)
    efficiency_wh_per_km = Column(Float, default=0.0)
    max_motor_temp_c = Column(Float, default=0.0)
    max_controller_temp_c = Column(Float, default=0.0)
    telemetry_blob = Column(Text, nullable=True)  # JSON or compressed track

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, index=True)
    deleted_at = Column(DateTime, nullable=True, index=True)

    user = relationship("User", back_populates="rides")


class MapFavoriteModel(Base):
    __tablename__ = "map_favorites"

    id = Column(String(64), primary_key=True, index=True)
    user_id = Column(String(64), ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String(128), nullable=False)
    subtitle = Column(String(255), default="")
    lat = Column(Float, nullable=False)
    lon = Column(Float, nullable=False)
    type = Column(String(32), default="custom")  # home, work, custom, recent
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, index=True)
    deleted_at = Column(DateTime, nullable=True, index=True)

    user = relationship("User", back_populates="map_favorites")


class RangeCalibrationModel(Base):
    __tablename__ = "range_calibrations"

    controller_id = Column(String(64), primary_key=True, index=True)
    user_id = Column(String(64), ForeignKey("users.id"), primary_key=True, index=True)
    learned_capacity_wh = Column(Float, default=1800.0)
    soc_confidence = Column(Float, default=0.5)
    consumption_history_json = Column(Text, default="[]")
    min_voltage_v = Column(Float, default=60.0)
    max_voltage_v = Column(Float, default=84.0)
    updated_at = Column(DateTime, default=datetime.utcnow, index=True)

    user = relationship("User", back_populates="range_calibrations")


def init_db():
    os.makedirs("./data", exist_ok=True)
    Base.metadata.create_all(bind=engine)
    # Enable WAL mode for SQLite for high-concurrency read/writes
    if "sqlite" in DATABASE_URL:
        with engine.connect() as connection:
            connection.exec_driver_sql("PRAGMA journal_mode=WAL;")
