"""
Test creating an appointment with dr__yehia@doctor.com
"""
import requests

BASE_URL = "http://127.0.0.1:8000"

def test_create():
    print("Logging in as dr__yehia@doctor.com...")
    login_resp = requests.post(f"{BASE_URL}/api/auth/login", json={"email": "dr__yehia@doctor.com", "password": "password123"})
    if login_resp.status_code != 200:
        print(f"Login failed: {login_resp.text}")
        return

    token = login_resp.json().get("access_token")
    headers = {"Authorization": f"Bearer {token}"}

    # Fetch patients to get a valid patient_id
    pts_resp = requests.get(f"{BASE_URL}/api/patients", headers=headers)
    if pts_resp.status_code != 200 or not pts_resp.json():
        print("Failed to fetch patients")
        return
    
    patient = pts_resp.json()[0]
    print(f"Target Patient: {patient['name']} (ID: {patient['id']})")

    payload = {
        "patient_id": patient["id"],
        "date": "2026-08-05",
        "time": "10:30 AM",
        "type": "Checkup",
        "condition": "Routine Checkup",
        "status": "pending"
    }

    print("Posting new appointment...")
    resp = requests.post(f"{BASE_URL}/api/appointments", json=payload, headers=headers)
    print(f"Response Status: {resp.status_code}")
    print(f"Response Body: {resp.text}")

if __name__ == "__main__":
    test_create()
