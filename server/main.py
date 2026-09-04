import uuid
from datetime import datetime
from typing import Optional
from fastapi import FastAPI, Depends, HTTPException, status, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from models import (
    init_db,
    User,
    Bike,
    TuningProfileModel,
    RideModel,
    MapFavoriteModel,
    RangeCalibrationModel,
)
from auth import (
    get_db,
    get_password_hash,
    verify_password,
    create_access_token,
    get_current_user,
)
from schemas import (
    UserRegister,
    UserLogin,
    TokenResponse,
    UserOut,
    SyncPushRequest,
    SyncPushResponse,
    SyncPullResponse,
    BikeSyncItem,
    TuningProfileSyncItem,
    RideSyncItem,
    MapFavoriteSyncItem,
    RangeCalibrationSyncItem,
)

init_db()

app = FastAPI(
    title="ArcDash Cloud Sync API",
    version="1.0.0",
    description="Offline-First Cloud Sync Backend for ArcDash E-Moto Telemetry & Tuning",
)

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    import logging
    logging.error(f"422 Validation Error on {request.url}: {exc.errors()}")
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"detail": exc.errors(), "body": str(exc.body)},
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok", "server_time": datetime.utcnow().isoformat()}


# ==========================================
# AUTH ENDPOINTS
# ==========================================
@app.post("/api/v1/auth/register", response_model=TokenResponse)
def register(req: UserRegister, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.username == req.username).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Benutzername bereits vergeben",
        )

    if req.email:
        existing_email = db.query(User).filter(User.email == req.email).first()
        if existing_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="E-Mail-Adresse bereits registriert",
            )

    user = User(
        id=str(uuid.uuid4()),
        username=req.username,
        email=req.email,
        password_hash=get_password_hash(req.password),
        created_at=datetime.utcnow(),
        last_login=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    token = create_access_token(data={"sub": user.id, "username": user.username})
    return TokenResponse(
        access_token=token,
        user_id=user.id,
        username=user.username,
    )


@app.post("/api/v1/auth/login", response_model=TokenResponse)
def login(req: UserLogin, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == req.username).first()
    if not user or not verify_password(req.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Ungültiger Benutzername oder Passwort",
        )

    user.last_login = datetime.utcnow()
    db.commit()

    token = create_access_token(data={"sub": user.id, "username": user.username})
    return TokenResponse(
        access_token=token,
        user_id=user.id,
        username=user.username,
    )


@app.get("/api/v1/auth/me", response_model=UserOut)
def me(current_user: User = Depends(get_current_user)):
    return current_user


# ==========================================
# SYNC ENDPOINTS (Delta Sync & Last-Write-Wins)
# ==========================================
@app.post("/api/v1/sync/push", response_model=SyncPushResponse)
def sync_push(
    payload: SyncPushRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    server_time = datetime.utcnow()

    # 1. Process Bikes
    bikes_count = 0
    for b in payload.bikes:
        b_created = b.created_at or server_time
        b_updated = b.updated_at or server_time
        existing = (
            db.query(Bike)
            .filter(Bike.id == b.id, Bike.user_id == current_user.id)
            .first()
        )
        if existing:
            # Last-Write-Wins: only update if incoming is newer or equal
            if b_updated >= existing.updated_at:
                existing.name = b.name
                existing.controller_id = b.controller_id
                existing.controller_name = b.controller_name
                existing.bms_id = b.bms_id
                existing.bms_name = b.bms_name
                existing.is_auto_connect = b.is_auto_connect
                existing.updated_at = b_updated
                existing.deleted_at = b.deleted_at
                bikes_count += 1
        else:
            new_bike = Bike(
                id=b.id,
                user_id=current_user.id,
                name=b.name,
                controller_id=b.controller_id,
                controller_name=b.controller_name,
                bms_id=b.bms_id,
                bms_name=b.bms_name,
                is_auto_connect=b.is_auto_connect,
                created_at=b_created,
                updated_at=b_updated,
                deleted_at=b.deleted_at,
            )
            db.add(new_bike)
            bikes_count += 1

    # 2. Process Tuning Profiles
    profiles_count = 0
    for p in payload.tuning_profiles:
        p_created = p.created_at or server_time
        p_updated = p.updated_at or server_time
        existing = (
            db.query(TuningProfileModel)
            .filter(
                TuningProfileModel.id == p.id,
                TuningProfileModel.user_id == current_user.id,
            )
            .first()
        )
        if existing:
            if p_updated >= existing.updated_at:
                existing.name = p.name
                existing.is_stock = p.is_stock
                existing.max_speed_kph = p.max_speed_kph
                existing.max_line_curr_a = p.max_line_curr_a
                existing.max_phase_curr_a = p.max_phase_curr_a
                existing.throttle_response = p.throttle_response
                existing.boost_seconds = p.boost_seconds
                existing.power_curve_json = p.power_curve_json
                existing.regen_curve_json = p.regen_curve_json
                existing.pin_mapping_json = p.pin_mapping_json
                existing.is_public = p.is_public
                existing.version = p.version
                existing.description = p.description
                existing.updated_at = p_updated
                existing.deleted_at = p.deleted_at
                profiles_count += 1
        else:
            new_profile = TuningProfileModel(
                id=p.id,
                user_id=current_user.id,
                name=p.name,
                is_stock=p.is_stock,
                max_speed_kph=p.max_speed_kph,
                max_line_curr_a=p.max_line_curr_a,
                max_phase_curr_a=p.max_phase_curr_a,
                throttle_response=p.throttle_response,
                boost_seconds=p.boost_seconds,
                power_curve_json=p.power_curve_json,
                regen_curve_json=p.regen_curve_json,
                pin_mapping_json=p.pin_mapping_json,
                is_public=p.is_public,
                version=p.version,
                description=p.description,
                created_at=p_created,
                updated_at=p_updated,
                deleted_at=p.deleted_at,
            )
            db.add(new_profile)
            profiles_count += 1

    # 3. Process Rides
    rides_count = 0
    for r in payload.rides:
        r_start = r.start_time or server_time
        r_end = r.end_time or server_time
        r_created = r.created_at or server_time
        r_updated = r.updated_at or server_time
        existing = (
            db.query(RideModel)
            .filter(RideModel.id == r.id, RideModel.user_id == current_user.id)
            .first()
        )
        if existing:
            if r_updated >= existing.updated_at:
                existing.bike_id = r.bike_id
                existing.start_time = r_start
                existing.end_time = r_end
                existing.duration_sec = r.duration_sec
                existing.distance_km = r.distance_km
                existing.avg_speed_kph = r.avg_speed_kph
                existing.max_speed_kph = r.max_speed_kph
                existing.energy_used_wh = r.energy_used_wh
                existing.efficiency_wh_per_km = r.efficiency_wh_per_km
                existing.max_motor_temp_c = r.max_motor_temp_c
                existing.max_controller_temp_c = r.max_controller_temp_c
                existing.telemetry_blob = r.telemetry_blob
                existing.updated_at = r_updated
                existing.deleted_at = r.deleted_at
                rides_count += 1
        else:
            new_ride = RideModel(
                id=r.id,
                user_id=current_user.id,
                bike_id=r.bike_id,
                start_time=r_start,
                end_time=r_end,
                duration_sec=r.duration_sec,
                distance_km=r.distance_km,
                avg_speed_kph=r.avg_speed_kph,
                max_speed_kph=r.max_speed_kph,
                energy_used_wh=r.energy_used_wh,
                efficiency_wh_per_km=r.efficiency_wh_per_km,
                max_motor_temp_c=r.max_motor_temp_c,
                max_controller_temp_c=r.max_controller_temp_c,
                telemetry_blob=r.telemetry_blob,
                created_at=r_created,
                updated_at=r_updated,
                deleted_at=r.deleted_at,
            )
            db.add(new_ride)
            rides_count += 1

    # 4. Process Map Favorites (Home, Work, Custom, Recents)
    favorites_count = 0
    for f in payload.map_favorites:
        f_created = f.created_at or server_time
        f_updated = f.updated_at or server_time
        existing = (
            db.query(MapFavoriteModel)
            .filter(
                MapFavoriteModel.id == f.id,
                MapFavoriteModel.user_id == current_user.id,
            )
            .first()
        )
        if existing:
            if f_updated >= existing.updated_at:
                existing.title = f.title
                existing.subtitle = f.subtitle
                existing.lat = f.lat
                existing.lon = f.lon
                existing.type = f.type
                existing.updated_at = f_updated
                existing.deleted_at = f.deleted_at
                favorites_count += 1
        else:
            new_fav = MapFavoriteModel(
                id=f.id,
                user_id=current_user.id,
                title=f.title,
                subtitle=f.subtitle,
                lat=f.lat,
                lon=f.lon,
                type=f.type,
                created_at=f_created,
                updated_at=f_updated,
                deleted_at=f.deleted_at,
            )
            db.add(new_fav)
            favorites_count += 1

    # 5. Process Range Calibrations
    calibrations_count = 0
    for c in payload.range_calibrations:
        c_updated = c.updated_at or server_time
        existing = (
            db.query(RangeCalibrationModel)
            .filter(
                RangeCalibrationModel.controller_id == c.controller_id,
                RangeCalibrationModel.user_id == current_user.id,
            )
            .first()
        )
        if existing:
            if c_updated >= existing.updated_at:
                existing.learned_capacity_wh = c.learned_capacity_wh
                existing.soc_confidence = c.soc_confidence
                existing.consumption_history_json = c.consumption_history_json
                existing.min_voltage_v = c.min_voltage_v
                existing.max_voltage_v = c.max_voltage_v
                existing.updated_at = c_updated
                calibrations_count += 1
        else:
            new_cal = RangeCalibrationModel(
                controller_id=c.controller_id,
                user_id=current_user.id,
                learned_capacity_wh=c.learned_capacity_wh,
                soc_confidence=c.soc_confidence,
                consumption_history_json=c.consumption_history_json,
                min_voltage_v=c.min_voltage_v,
                max_voltage_v=c.max_voltage_v,
                updated_at=c_updated,
            )
            db.add(new_cal)
            calibrations_count += 1

    db.commit()

    return SyncPushResponse(
        success=True,
        server_time=server_time,
        bikes_processed=bikes_count,
        tuning_profiles_processed=profiles_count,
        rides_processed=rides_count,
        map_favorites_processed=favorites_count,
        range_calibrations_processed=calibrations_count,
    )


@app.get("/api/v1/sync/pull", response_model=SyncPullResponse)
def sync_pull(
    since: Optional[datetime] = Query(None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    server_time = datetime.utcnow()

    # Query bikes
    bike_query = db.query(Bike).filter(Bike.user_id == current_user.id)
    if since:
        bike_query = bike_query.filter(Bike.updated_at > since)
    bikes = bike_query.all()

    # Query profiles
    profile_query = db.query(TuningProfileModel).filter(
        TuningProfileModel.user_id == current_user.id
    )
    if since:
        profile_query = profile_query.filter(TuningProfileModel.updated_at > since)
    profiles = profile_query.all()

    # Query rides
    ride_query = db.query(RideModel).filter(RideModel.user_id == current_user.id)
    if since:
        ride_query = ride_query.filter(RideModel.updated_at > since)
    rides = ride_query.all()

    # Query map favorites
    favorite_query = db.query(MapFavoriteModel).filter(
        MapFavoriteModel.user_id == current_user.id
    )
    if since:
        favorite_query = favorite_query.filter(MapFavoriteModel.updated_at > since)
    favorites = favorite_query.all()

    # Query range calibrations
    cal_query = db.query(RangeCalibrationModel).filter(
        RangeCalibrationModel.user_id == current_user.id
    )
    if since:
        cal_query = cal_query.filter(RangeCalibrationModel.updated_at > since)
    calibrations = cal_query.all()

    return SyncPullResponse(
        server_time=server_time,
        bikes=[
            BikeSyncItem(
                id=b.id,
                name=b.name,
                controller_id=b.controller_id,
                controller_name=b.controller_name,
                bms_id=b.bms_id,
                bms_name=b.bms_name,
                is_auto_connect=b.is_auto_connect,
                created_at=b.created_at,
                updated_at=b.updated_at,
                deleted_at=b.deleted_at,
            )
            for b in bikes
        ],
        tuning_profiles=[
            TuningProfileSyncItem(
                id=p.id,
                name=p.name,
                is_stock=p.is_stock,
                max_speed_kph=p.max_speed_kph,
                max_line_curr_a=p.max_line_curr_a,
                max_phase_curr_a=p.max_phase_curr_a,
                throttle_response=p.throttle_response,
                boost_seconds=p.boost_seconds,
                power_curve_json=p.power_curve_json,
                regen_curve_json=p.regen_curve_json,
                pin_mapping_json=p.pin_mapping_json,
                is_public=p.is_public,
                version=p.version,
                description=p.description,
                created_at=p.created_at,
                updated_at=p.updated_at,
                deleted_at=p.deleted_at,
            )
            for p in profiles
        ],
        rides=[
            RideSyncItem(
                id=r.id,
                bike_id=r.bike_id,
                start_time=r.start_time,
                end_time=r.end_time,
                duration_sec=r.duration_sec,
                distance_km=r.distance_km,
                avg_speed_kph=r.avg_speed_kph,
                max_speed_kph=r.max_speed_kph,
                energy_used_wh=r.energy_used_wh,
                efficiency_wh_per_km=r.efficiency_wh_per_km,
                max_motor_temp_c=r.max_motor_temp_c,
                max_controller_temp_c=r.max_controller_temp_c,
                telemetry_blob=r.telemetry_blob,
                created_at=r.created_at,
                updated_at=r.updated_at,
                deleted_at=r.deleted_at,
            )
            for r in rides
        ],
        map_favorites=[
            MapFavoriteSyncItem(
                id=f.id,
                title=f.title,
                subtitle=f.subtitle,
                lat=f.lat,
                lon=f.lon,
                type=f.type,
                created_at=f.created_at,
                updated_at=f.updated_at,
                deleted_at=f.deleted_at,
            )
            for f in favorites
        ],
        range_calibrations=[
            RangeCalibrationSyncItem(
                controller_id=c.controller_id,
                learned_capacity_wh=c.learned_capacity_wh,
                soc_confidence=c.soc_confidence,
                consumption_history_json=c.consumption_history_json,
                min_voltage_v=c.min_voltage_v,
                max_voltage_v=c.max_voltage_v,
                updated_at=c.updated_at,
            )
            for c in calibrations
        ],
    )
