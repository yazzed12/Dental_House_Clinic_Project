
import os
import smtplib
import logging
import json
import time
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

logger = logging.getLogger(__name__)

EMAIL_HOST = os.getenv("EMAIL_HOST", "smtp.gmail.com")
EMAIL_PORT = int(os.getenv("EMAIL_PORT", "587"))
EMAIL_USER = os.getenv("EMAIL_USER", "")
EMAIL_PASS = os.getenv("EMAIL_PASS", "")

TEST_EMAILS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_emails.json")

def save_code_to_test_file(email: str, code: str):
    """
    Saves the plain-text verification or reset code to a local JSON file.
    This allows automated integration tests to retrieve the code since the
    database stores only secure hashes.
    """
    try:
        data = {}
        if os.path.exists(TEST_EMAILS_PATH):
            with open(TEST_EMAILS_PATH, "r") as f:
                try:
                    data = json.load(f)
                except Exception:
                    data = {}
        
        data[email.strip().lower()] = {
            "code": code,
            "timestamp": time.time()
        }
        
        with open(TEST_EMAILS_PATH, "w") as f:
            json.dump(data, f)
            
        logger.info(f"Saved plain-text code for {email} to {TEST_EMAILS_PATH} for test automation.")
    except Exception as e:
        logger.error(f"Failed to write to test emails file: {e}")

def get_html_template(title: str, preheader: str, body_text: str, code: str) -> str:
    """
    Generates a premium HTML email template with matching clinic branding.
    """
    return f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>{title}</title>
  <style>
    body {{
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
      background-color: #f4f6f9;
      margin: 0;
      padding: 0;
      color: #333333;
    }}
    .container {{
      max-width: 600px;
      margin: 40px auto;
      background: #ffffff;
      border-radius: 16px;
      overflow: hidden;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.05);
    }}
    .header {{
      background: linear-gradient(135deg, #10b981, #059669);
      padding: 32px;
      text-align: center;
      color: #ffffff;
    }}
    .header h1 {{
      margin: 0;
      font-size: 24px;
      font-weight: 800;
    }}
    .content {{
      padding: 40px 32px;
      line-height: 1.6;
    }}
    .content p {{
      margin: 0 0 20px;
      font-size: 16px;
      color: #4b5563;
    }}
    .code-box {{
      background: #f0fdf4;
      border: 2px dashed #34d399;
      border-radius: 12px;
      text-align: center;
      padding: 24px;
      margin: 32px 0;
    }}
    .code-text {{
      font-family: 'Courier New', Courier, monospace;
      font-size: 36px;
      font-weight: 800;
      letter-spacing: 6px;
      color: #047857;
      margin: 0;
    }}
    .footer {{
      background-color: #f9fafb;
      padding: 24px;
      text-align: center;
      font-size: 13px;
      color: #9ca3af;
      border-top: 1px solid #f3f4f6;
    }}
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Smart Dental Clinic</h1>
    </div>
    <div class="content">
      <p>{preheader}</p>
      <p>{body_text}</p>
      <div class="code-box">
        <div class="code-text">{code}</div>
      </div>
      <p>If you did not make this request, please ignore this email or contact support if you have concerns.</p>
    </div>
    <div class="footer">
      &copy; 2026 Smart Dental Clinic. All rights reserved.
    </div>
  </div>
</body>
</html>
"""

def send_smtp_email(to_email: str, subject: str, plain_body: str, html_body: str) -> bool:
    """
    Core SMTP sender with TLS login and retry mechanism (up to 2 retries).
    """
    if not EMAIL_USER or not EMAIL_PASS:
        logger.error("SMTP sending skipped: EMAIL_USER or EMAIL_PASS not configured in environment variables.")
        return False
        
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = EMAIL_USER
    msg["To"] = to_email

    msg.attach(MIMEText(plain_body, "plain"))
    msg.attach(MIMEText(html_body, "html"))

    retries = 2
    for attempt in range(retries + 1):
        try:
            logger.info(f"Attempting to send email to {to_email} (Attempt {attempt + 1})...")
            server = smtplib.SMTP(EMAIL_HOST, EMAIL_PORT, timeout=10)
            server.starttls()
            server.login(EMAIL_USER, EMAIL_PASS)
            server.sendmail(EMAIL_USER, to_email, msg.as_string())
            server.quit()
            logger.info(f"Email successfully sent to {to_email} via SMTP.")
            return True
        except Exception as e:
            logger.error(f"SMTP send failed on attempt {attempt + 1}: {e}")
            if attempt < retries:
                time.sleep(1.5)  # Wait before retry
                
    return False

def send_verification_email(to_email: str, code: str):
    """
    Sends account verification code to user's personal email.
    """
    # Save code locally for test runners
    save_code_to_test_file(to_email, code)
    
    subject = "Verify Your Account"
    plain_body = f"Welcome to Smart Dental Clinic!\n\nYour verification code is: {code}\n\nThis code expires in 10 minutes."
    html_body = get_html_template(
        title="Verify Your Account",
        preheader="Welcome to Smart Dental Clinic!",
        body_text="Please use the following 6-digit verification code to complete your signup:",
        code=code
    )
    
    send_smtp_email(to_email, subject, plain_body, html_body)

def send_reset_email(to_email: str, code: str):
    """
    Sends password reset code to user's personal/recovery email.
    """
    # Save code locally for test runners
    save_code_to_test_file(to_email, code)
    
    subject = "Reset Your Password"
    plain_body = f"Hello,\n\nYour password reset code is: {code}\n\nThis code expires in 10 minutes."
    html_body = get_html_template(
        title="Reset Your Password",
        preheader="Password Reset Request",
        body_text="We received a request to reset your password. Please use the following 6-digit code to complete the process:",
        code=code
    )
    
    send_smtp_email(to_email, subject, plain_body, html_body)
