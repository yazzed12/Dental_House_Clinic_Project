import urllib.request
import urllib.parse
import json
import sqlite3
import os

BASE_URL = "http://127.0.0.1:8000"

def make_request(path, method="POST", data=None):
    url = f"{BASE_URL}{path}"
    headers = {"Content-Type": "application/json"}
    req_data = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=req_data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            res_data = response.read().decode("utf-8")
            return response.status, json.loads(res_data) if res_data else {}
    except urllib.error.HTTPError as e:
        res_data = e.read().decode("utf-8")
        try:
            err_json = json.loads(res_data)
        except Exception:
            err_json = res_data
        return e.code, err_json

def get_verification_code(username):
    db_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pending_users.db")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT verification_code FROM pending_registrations WHERE username = ?", (username.lower(),))
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else None

def get_reset_token(clinic_email):
    db_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pending_users.db")
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT reset_token FROM password_resets WHERE clinic_email = ?", (clinic_email.lower(),))
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else None

def delete_user_if_exists(username, clinic_email):
    # Clean database so this scenario is repeatable
    db_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "clinic.db")
    if not os.path.exists(db_path):
        return
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM users WHERE username = ? OR email = ?", (username, clinic_email))
    conn.commit()
    conn.close()
    
    # Also clean pending mappings
    db_pending = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pending_users.db")
    if os.path.exists(db_pending):
        conn2 = sqlite3.connect(db_pending)
        cursor2 = conn2.cursor()
        cursor2.execute("DELETE FROM email_mappings WHERE clinic_email = ?", (clinic_email,))
        cursor2.execute("DELETE FROM pending_registrations WHERE username = ?", (username,))
        cursor2.execute("DELETE FROM password_resets WHERE clinic_email = ?", (clinic_email,))
        conn2.commit()
        conn2.close()

def run_e2e():
    username = "testdoctor"
    password = "Test12345!"
    full_name = "Test Doctor"
    role = "Doctor"
    personal_email = "yazzedstd1@gmail.com"
    clinic_email = "testdoctor@doctor.com"
    new_password = "NewTest123!"
    
    # Cleanup previous runs
    delete_user_if_exists(username, clinic_email)
    
    results = []
    
    print("\nStarting End-to-End Authentication System Test...\n")
    
    # ----------------------------------------------------
    # 1. REGISTER
    # ----------------------------------------------------
    print("[1] Registering Account...")
    reg_payload = {
        "username": username,
        "password": password,
        "full_name": full_name,
        "role": role,
        "personal_email": personal_email,
        "email": clinic_email # frontend generated email placeholder
    }
    status, body = make_request("/api/auth/register", "POST", reg_payload)
    print(f"    Register Status: {status}")
    print(f"    Register Response: {body}")
    
    if status == 200 and body.get("status") == "success":
        results.append("1. Registration -> SUCCESS (Verification code sent)")
    else:
        results.append(f"1. Registration -> FAILED ({body})")
        return results
        
    # ----------------------------------------------------
    # 2. VERIFY ACCOUNT
    # ----------------------------------------------------
    print("\n[2] Verifying Account...")
    code = get_verification_code(username)
    print(f"    Retrieved Verification Code: {code}")
    
    verify_payload = {
        "username": username,
        "code": code
    }
    status, body = make_request("/api/auth/verify", "POST", verify_payload)
    print(f"    Verify Status: {status}")
    print(f"    Verify Response: {body}")
    
    if status == 200 and body.get("access_token"):
        results.append("2. Verification -> SUCCESS (User created, token returned)")
    else:
        results.append(f"2. Verification -> FAILED ({body})")
        return results
        
    # ----------------------------------------------------
    # 3. LOGIN (Clinic Email ONLY)
    # ----------------------------------------------------
    print("\n[3] Logging in using Clinic Email...")
    login_payload = {
        "email": clinic_email,
        "password": password
    }
    status, body = make_request("/api/auth/login", "POST", login_payload)
    print(f"    Clinic Email Login Status: {status}")
    print(f"    Clinic Email Login Response: {body}")
    
    clinic_login_ok = (status == 200 and body.get("access_token"))
    
    print("    Verifying Login using Personal Email fails...")
    login_personal_payload = {
        "email": personal_email,
        "password": password
    }
    status_fail, body_fail = make_request("/api/auth/login", "POST", login_personal_payload)
    print(f"    Personal Email Login Status: {status_fail}")
    print(f"    Personal Email Login Response: {body_fail}")
    
    personal_login_failed = (status_fail == 400)
    
    if clinic_login_ok and personal_login_failed:
        results.append("3. Login (Clinic Email ONLY) -> SUCCESS (Login works for clinic email, fails for personal email)")
    else:
        results.append(f"3. Login (Clinic Email ONLY) -> FAILED (Clinic OK: {clinic_login_ok}, Personal Failed: {personal_login_failed})")
        
    # ----------------------------------------------------
    # 4. FORGET PASSWORD
    # ----------------------------------------------------
    print("\n[4] Requesting Password Reset...")
    forgot_payload = {
        "clinic_email": clinic_email
    }
    status, body = make_request("/api/auth/forgot-password", "POST", forgot_payload)
    print(f"    Forgot Password Status: {status}")
    print(f"    Forgot Password Response: {body}")
    
    if status == 200 and body.get("personal_email") == personal_email:
        results.append("4. Forget Password -> SUCCESS (Reset token generated, sent to personal email)")
    else:
        results.append(f"4. Forget Password -> FAILED ({body})")
        
    # ----------------------------------------------------
    # 5. RESET PASSWORD
    # ----------------------------------------------------
    print("\n[5] Resetting Password...")
    token = get_reset_token(clinic_email)
    print(f"    Retrieved Reset Token: {token}")
    
    reset_payload = {
        "token": token,
        "new_password": new_password
    }
    status, body = make_request("/api/auth/reset-password", "POST", reset_payload)
    print(f"    Reset Password Status: {status}")
    print(f"    Reset Password Response: {body}")
    
    if status == 200 and body.get("status") == "success":
        results.append("5. Reset Password -> SUCCESS (Password updated)")
    else:
        results.append(f"5. Reset Password -> FAILED ({body})")
        
    # ----------------------------------------------------
    # 6. LOGIN WITH NEW PASSWORD
    # ----------------------------------------------------
    print("\n[6] Logging in with New Password...")
    login_new_payload = {
        "email": clinic_email,
        "password": new_password
    }
    status, body = make_request("/api/auth/login", "POST", login_new_payload)
    print(f"    New Password Login Status: {status}")
    print(f"    New Password Login Response: {body}")
    
    if status == 200 and body.get("access_token"):
        results.append("6. Login with New Password -> SUCCESS")
    else:
        results.append(f"6. Login with New Password -> FAILED ({body})")
        
    # ----------------------------------------------------
    # Print Summary Report
    # ----------------------------------------------------
    print("\n" + "="*50)
    print("           AUTHENTICATION SYSTEM TEST REPORT")
    print("="*50)
    for r in results:
        print(f"  {r}")
    print("="*50 + "\n")
    
if __name__ == "__main__":
    run_e2e()
