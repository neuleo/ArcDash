from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime


# --- Auth Schemas ---
class UserRegister(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=6)
    email: Optional[str] = None


class UserLogin(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    username: str


class UserOut(BaseModel):
    id: str
    username: str
    email: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


# --- Bike Sync Schemas ---
class BikeSyncItem(BaseModel):
    id: str
    name: str
    controller_id: str = ""
    controller_name: str = "FarDriver Controller"
    bms_id: str = ""
    bms_name: str = "ANT BMS"
    is_auto_connect: bool = False
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    deleted_at: Optional[datetime] = None


# --- Tuning Profile Sync Schemas ---
class TuningProfileSyncItem(BaseModel):
    id: str
    name: str
    is_stock: bool = False
    max_speed_kph: float = 45.0
    max_line_curr_a: float = 80.0
    max_phase_curr_a: float = 200.0
    throttle_response: int = 1
    boost_seconds: int = 10
    power_curve_json: str = "[]"
    regen_curve_json: str = "[]"
    pin_mapping_json: str = "{}"
    is_public: bool = False
    version: int = 1
    description: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    deleted_at: Optional[datetime] = None


# --- Ride Sync Schemas ---
class RideSyncItem(BaseModel):
    id: str
    bike_id: Optional[str] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    duration_sec: int = 0
    distance_km: float = 0.0
    avg_speed_kph: float = 0.0
    max_speed_kph: float = 0.0
    energy_used_wh: float = 0.0
    efficiency_wh_per_km: float = 0.0
    max_motor_temp_c: float = 0.0
    max_controller_temp_c: float = 0.0
    telemetry_blob: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    deleted_at: Optional[datetime] = None


# --- Map Favorites Sync Schemas ---
class MapFavoriteSyncItem(BaseModel):
    id: str
    title: str
    subtitle: str = ""
    lat: float
    lon: float
    type: str = "custom"  # home, work, custom, recent
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    deleted_at: Optional[datetime] = None


# --- Range Calibration Sync Schemas ---
class RangeCalibrationSyncItem(BaseModel):
    controller_id: str
    learned_capacity_wh: Optional[float] = 1800.0
    soc_confidence: Optional[float] = 0.5
    consumption_history_json: Optional[str] = "[]"
    min_voltage_v: Optional[float] = 60.0
    max_voltage_v: Optional[float] = 84.0
    updated_at: Optional[datetime] = None


# --- Bidirectional Sync Payload Schemas ---
class SyncPushRequest(BaseModel):
    bikes: List[BikeSyncItem] = []
    tuning_profiles: List[TuningProfileSyncItem] = []
    rides: List[RideSyncItem] = []
    map_favorites: List[MapFavoriteSyncItem] = []
    range_calibrations: List[RangeCalibrationSyncItem] = []


class SyncPushResponse(BaseModel):
    success: bool
    server_time: datetime
    bikes_processed: int
    tuning_profiles_processed: int
    rides_processed: int
    map_favorites_processed: int
    range_calibrations_processed: int


class SyncPullResponse(BaseModel):
    server_time: datetime
    bikes: List[BikeSyncItem]
    tuning_profiles: List[TuningProfileSyncItem]
    rides: List[RideSyncItem]
    map_favorites: List[MapFavoriteSyncItem]
    range_calibrations: List[RangeCalibrationSyncItem]
