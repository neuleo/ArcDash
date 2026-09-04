import pytest
from datetime import datetime
from fastapi.testclient import TestClient
from main import app
from models import init_db

init_db()
client = TestClient(app)


def test_health():
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"


def test_register_login_and_sync_cycle():
    # 1. Register
    username = f"user_{int(datetime.utcnow().timestamp())}"
    reg_payload = {
        "username": username,
        "password": "secretpassword123",
        "email": f"{username}@example.com",
    }
    reg_res = client.post("/api/v1/auth/register", json=reg_payload)
    assert reg_res.status_code == 200
    token = reg_res.json()["access_token"]
    assert token is not None

    headers = {"Authorization": f"Bearer {token}"}

    # 2. Test Me
    me_res = client.get("/api/v1/auth/me", headers=headers)
    assert me_res.status_code == 200
    assert me_res.json()["username"] == username

    # 3. Push a Bike and Tuning Profile
    now = datetime.utcnow().isoformat()
    push_payload = {
        "bikes": [
            {
                "id": "bike_test_1",
                "name": "Arctic Leopard L1E (Test)",
                "controller_id": "FD:11:22:33",
                "controller_name": "FarDriver 72530",
                "bms_id": "ANT:44:55:66",
                "bms_name": "ANT BMS",
                "is_auto_connect": True,
                "created_at": now,
                "updated_at": now,
                "deleted_at": None,
            }
        ],
        "tuning_profiles": [
            {
                "id": "prof_test_1",
                "name": "Enduro Boost 75kmh",
                "is_stock": False,
                "max_speed_kph": 75.0,
                "max_line_curr_a": 120.0,
                "max_phase_curr_a": 280.0,
                "throttle_response": 2,
                "boost_seconds": 15,
                "power_curve_json": "[]",
                "regen_curve_json": "[]",
                "pin_mapping_json": "{}",
                "is_public": False,
                "version": 1,
                "created_at": now,
                "updated_at": now,
                "deleted_at": None,
            }
        ],
        "rides": [],
    }

    push_res = client.post("/api/v1/sync/push", headers=headers, json=push_payload)
    assert push_res.status_code == 200
    push_data = push_res.json()
    assert push_data["success"] is True
    assert push_data["bikes_processed"] == 1
    assert push_data["tuning_profiles_processed"] == 1

    # 4. Pull to verify data persistence & retrieval
    pull_res = client.get("/api/v1/sync/pull", headers=headers)
    assert pull_res.status_code == 200
    pull_data = pull_res.json()
    assert len(pull_data["bikes"]) == 1
    assert pull_data["bikes"][0]["id"] == "bike_test_1"
    assert pull_data["bikes"][0]["name"] == "Arctic Leopard L1E (Test)"
    assert len(pull_data["tuning_profiles"]) == 1
    assert pull_data["tuning_profiles"][0]["name"] == "Enduro Boost 75kmh"

    # 5. Soft-Delete test
    push_payload["bikes"][0]["deleted_at"] = datetime.utcnow().isoformat()
    push_res_del = client.post("/api/v1/sync/push", headers=headers, json=push_payload)
    assert push_res_del.status_code == 200

    pull_res2 = client.get("/api/v1/sync/pull", headers=headers)
    assert pull_res2.status_code == 200
    assert pull_res2.json()["bikes"][0]["deleted_at"] is not None
