#!/usr/bin/env python3
"""
Autonomous Clinic Automation & Synchronization System
Handles email commands (IMAP), sends notifications (SMTP), syncs repository to GitHub,
monitors sqlite DB events, and runs background worker tasks securely.
"""

import os
import sys
import re
import time
import argparse
import logging
import sqlite3
import subprocess
import smtplib
import imaplib
import email
from email.header import decode_header
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import datetime
from typing import Callable, Any, Dict, List, Optional
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Reconfigure standard streams to avoid UnicodeEncodeError on Windows terminals
if sys.platform.startswith("win"):
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
        if hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")
    except Exception:
        pass

# Setup paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE_PATH = os.path.join(BASE_DIR, "automation.log")
DB_FILE_PATH = os.path.join(BASE_DIR, "clinic.db")


# ─── RETRY & LOGGING SYSTEM ──────────────────────────────────────────────────

class SecretsMaskingFilter(logging.Filter):
    """
    Logging filter that automatically redacts configured secrets and sensitive tokens
    from any log messages before they are printed or written to disk.
    """
    def __init__(self, secrets_to_mask: List[str] = None):
        super().__init__()
        self.secrets = [s for s in (secrets_to_mask or []) if s]

    def filter(self, record: logging.LogRecord) -> bool:
        if not self.secrets:
            return True
        
        # Convert message to string
        msg = str(record.msg)
        for secret in self.secrets:
            # Mask the exact secret value if it appears in log
            msg = msg.replace(secret, "[REDACTED]")
        record.msg = msg
        return True


def setup_logger(secrets_to_mask: List[str] = None) -> logging.Logger:
    """
    Sets up the central logger writing to automation.log and console
    while applying the secrets masking filter.
    """
    logger = logging.getLogger("ClinicAutomation")
    logger.setLevel(logging.INFO)
    logger.propagate = False # Prevent doubling of logs in root logger
    
    # Reset existing handlers if re-called
    if logger.handlers:
        logger.handlers.clear()

    formatter = logging.Formatter(
        "[%(asctime)s] [%(levelname)s] [%(filename)s:%(lineno)d] %(message)s"
    )

    # File Handler
    file_handler = logging.FileHandler(LOG_FILE_PATH, encoding="utf-8")
    file_handler.setFormatter(formatter)
    
    # Console Handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)

    # Apply secrets masking filter
    masking_filter = SecretsMaskingFilter(secrets_to_mask)
    file_handler.addFilter(masking_filter)
    console_handler.addFilter(masking_filter)

    logger.addHandler(file_handler)
    logger.addHandler(console_handler)

    return logger


def retry(max_attempts: int = 3, delay: float = 2.0, backoff: float = 2.0):
    """
    Decorator for retrying a function with exponential backoff on exceptions.
    """
    def decorator(func: Callable[..., Any]):
        def wrapper(*args, **kwargs):
            logger = logging.getLogger("ClinicAutomation")
            current_delay = delay
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    logger.warning(
                        f"Exception in '{func.__name__}' (Attempt {attempt}/{max_attempts}): {e}"
                    )
                    if attempt == max_attempts:
                        logger.error(f"Function '{func.__name__}' failed after {max_attempts} attempts.")
                        raise e
                    time.sleep(current_delay)
                    current_delay *= backoff
        return wrapper
    return decorator


# ─── AUTHENTICATION & SECURITY MANAGER ───────────────────────────────────────

class AuthManager:
    """
    Manages loading, validating, and protecting sensitive configurations and credentials.
    """
    def __init__(self):
        self.email_host = os.getenv("EMAIL_HOST", "smtp.gmail.com")
        try:
            self.email_port = int(os.getenv("EMAIL_PORT", "587"))
        except (TypeError, ValueError):
            self.email_port = 587
            
        self.email_user = os.getenv("EMAIL_USER", "").strip()
        self.email_pass = os.getenv("EMAIL_PASS", "").strip()
        self.email_imap_server = os.getenv("EMAIL_IMAP_SERVER", "imap.gmail.com")
        self.github_token = os.getenv("GITHUB_TOKEN", "").strip()

    def validate_credentials(self) -> bool:
        """
        Validates that all essential environment variables are set.
        """
        missing = []
        if not self.email_user:
            missing.append("EMAIL_USER")
        if not self.email_pass:
            missing.append("EMAIL_PASS")
        if not self.github_token:
            missing.append("GITHUB_TOKEN")
            
        if missing:
            # We log the warning but don't print the actual tokens/passwords
            print(f"[Warning] Missing environment variables: {', '.join(missing)}")
            return False
        return True

    def get_secrets_list(self) -> List[str]:
        """
        Returns a list of sensitive values to be redacted in logs.
        """
        return [self.email_pass, self.github_token]


# Initialize configuration & logger
auth_mgr = AuthManager()
logger = setup_logger(auth_mgr.get_secrets_list())


# ─── EMAIL INTEGRATION SERVICE ───────────────────────────────────────────────

class EmailService:
    """
    Provides secure SMTP (sending) and IMAP (reading & parsing commands) email integrations.
    """
    def __init__(self, auth: AuthManager, test_mode: bool = False):
        self.auth = auth
        self.test_mode = test_mode
        self.mock_sent_emails: List[Dict[str, Any]] = []
        self.mock_incoming_emails: List[Dict[str, Any]] = [
            {
                "sender": "clinic_admin@gmail.com",
                "subject": "CLINIC_CMD: STATUS",
                "command": "STATUS",
                "body": "Provide clinic database health statistics."
            },
            {
                "sender": "head_doctor@gmail.com",
                "subject": "CLINIC_CMD: ALERT",
                "command": "ALERT",
                "body": "Alert: Dental X-Ray machine #2 requires immediate calibration/inspection."
            }
        ]

    @retry(max_attempts=3, delay=1.5, backoff=2.0)
    def send_email(self, to_email: str, subject: str, plain_body: str, html_body: Optional[str] = None) -> bool:
        """
        Sends an email notification via SMTP TLS.
        """
        logger.info(f"Preparing to send email to {to_email} with subject: '{subject}'")
        
        if self.test_mode:
            logger.info("[MOCK SMTP] Successfully sent mock email (Test Mode active)")
            self.mock_sent_emails.append({
                "to": to_email,
                "subject": subject,
                "body": plain_body
            })
            return True

        if not self.auth.email_user or not self.auth.email_pass:
            logger.error("SMTP sending skipped: Email credentials not configured.")
            return False

        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = self.auth.email_user
        msg["To"] = to_email

        msg.attach(MIMEText(plain_body, "plain"))
        if html_body:
            msg.attach(MIMEText(html_body, "html"))

        try:
            server = smtplib.SMTP(self.auth.email_host, self.auth.email_port, timeout=10)
            server.starttls()
            server.login(self.auth.email_user, self.auth.email_pass)
            server.sendmail(self.auth.email_user, to_email, msg.as_string())
            server.quit()
            logger.info(f"Email successfully sent to {to_email}")
            return True
        except Exception as e:
            logger.error(f"Failed to send email to {to_email} via SMTP: {e}")
            raise e

    @retry(max_attempts=2, delay=2.0, backoff=2.0)
    def poll_inbox_commands(self) -> List[Dict[str, Any]]:
        """
        Checks the IMAP server for incoming messages, parses subjects matching
        'CLINIC_CMD: <COMMAND>', and returns list of parsed commands.
        """
        logger.info("Polling inbox for new CLINIC_CMD commands...")
        commands = []

        if self.test_mode:
            logger.info(f"[MOCK IMAP] Returning {len(self.mock_incoming_emails)} mock command emails")
            # Return copy of mock emails and clear so we don't loop endlessly in test
            cmds = list(self.mock_incoming_emails)
            self.mock_incoming_emails.clear()
            return cmds

        if not self.auth.email_user or not self.auth.email_pass:
            logger.warning("IMAP polling skipped: Email credentials not configured.")
            return commands

        try:
            # Connect to IMAP server using SSL
            mail = imaplib.IMAP4_SSL(self.auth.email_imap_server, 993, timeout=15)
            mail.login(self.auth.email_user, self.auth.email_pass)
            mail.select("inbox")

            # Search for unread/unseen messages
            status, response_data = mail.search(None, "UNSEEN")
            if status != "OK":
                logger.error("IMAP search failed")
                return commands

            mail_ids = response_data[0].split()
            logger.info(f"Found {len(mail_ids)} unread emails in inbox.")

            for m_id in mail_ids:
                status, msg_data = mail.fetch(m_id, "(RFC822)")
                if status != "OK":
                    continue
                
                raw_email = msg_data[0][1]
                msg = email.message_from_bytes(raw_email)

                # Decode subject
                subject_raw = msg.get("Subject", "")
                decoded_header_data = decode_header(subject_raw)
                subject = ""
                for bytes_str, charset in decoded_header_data:
                    if isinstance(bytes_str, bytes):
                        subject += bytes_str.decode(charset or "utf-8", errors="ignore")
                    else:
                        subject += str(bytes_str)

                # Fetch sender address
                sender = msg.get("From", "")
                
                # Check for command prefix
                match = re.match(r"^CLINIC_CMD:\s*(\w+)", subject, re.IGNORECASE)
                if match:
                    command_name = match.group(1).upper()
                    
                    # Fetch body
                    body = ""
                    if msg.is_multipart():
                        for part in msg.walk():
                            if part.get_content_type() == "text/plain":
                                body = part.get_payload(decode=True).decode(errors="ignore")
                                break
                    else:
                        body = msg.get_payload(decode=True).decode(errors="ignore")

                    commands.append({
                        "id": m_id,
                        "sender": sender,
                        "subject": subject,
                        "command": command_name,
                        "body": body.strip()
                    })
                    logger.info(f"Successfully detected and parsed command '{command_name}' from {sender}")
                    
                    # Mark email as read / seen
                    mail.store(m_id, "+FLAGS", "\\Seen")

            mail.close()
            mail.logout()
        except Exception as e:
            logger.error(f"Error during IMAP polling: {e}")
            raise e

        return commands


# ─── GITHUB REPOSITORY SYNC ─────────────────────────────────────────────────

class GitHubSync:
    """
    Subprocess wrapper for local Git commands ensuring clinic files, backups,
    and settings are safely synced to GitHub without blocking or crashing.
    """
    def __init__(self, auth: AuthManager):
        self.auth = auth
        self.git_dir = os.path.dirname(BASE_DIR) # Workspace root

    def run_git_cmd(self, cmd: List[str]) -> str:
        """
        Executes a git command in the workspace directory.
        """
        # Inject the GITHUB_TOKEN securely if running operations on origin/remote
        env = os.environ.copy()
        if self.auth.github_token:
            env["GITHUB_TOKEN"] = self.auth.github_token

        logger.info(f"Running git command: git {' '.join(cmd[1:])}")
        result = subprocess.run(
            cmd,
            cwd=self.git_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            timeout=30
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"Git command failed: {result.stderr.strip()}")
            
        return result.stdout.strip()

    def check_status(self) -> str:
        """
        Checks local changes.
        """
        try:
            return self.run_git_cmd(["git", "status", "--porcelain"])
        except Exception as e:
            logger.error(f"Failed to check git status: {e}")
            return ""

    def commit_and_push(self, custom_message: Optional[str] = None) -> bool:
        """
        Safely stages changes, commits them with an auto-generated timestamp, and pushes.
        """
        try:
            # Check status first
            status = self.check_status()
            if not status:
                logger.info("GitHub sync: No local changes to commit.")
                return True

            logger.info("Local changes detected. Proceeding with Git sync...")
            
            # Stage changes
            self.run_git_cmd(["git", "add", "."])
            
            # Commit changes
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            msg = custom_message or f"chore(sync): automated clinic system backup at {timestamp}"
            self.run_git_cmd(["git", "commit", "-m", msg])
            
            # Push changes safely
            self.run_git_cmd(["git", "push", "origin", "main"])
            logger.info("GitHub sync: Successfully committed and pushed changes.")
            return True
        except Exception as e:
            logger.error(f"Fail-safe: GitHub sync operation encountered an error: {e}")
            return False


# ─── DATABASE MONITOR & POLLE ────────────────────────────────────────────────

class DatabaseMonitor:
    """
    Monitors sqlite database for incoming urgent patient cases or bookings,
    triggering alerts and logging notifications inside the app.
    """
    def __init__(self, db_path: str, email_svc: EmailService):
        self.db_path = db_path
        self.email_svc = email_svc
        self.last_checked_appointment_id = 0
        self.init_last_checked_id()

    def get_db_connection(self):
        """
        Establishes raw SQLite connection.
        """
        return sqlite3.connect(self.db_path)

    def init_last_checked_id(self):
        """
        Finds the maximum appointment ID on startup to prevent alerting on historical entries.
        """
        if not os.path.exists(self.db_path):
            logger.warning(f"clinic.db not found at {self.db_path}. database monitor will resume with ID 0.")
            return
            
        try:
            conn = self.get_db_connection()
            cursor = conn.cursor()
            # Ensure appointments table exists first
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='appointments'")
            if cursor.fetchone():
                cursor.execute("SELECT MAX(id) FROM appointments")
                row = cursor.fetchone()
                if row and row[0] is not None:
                    self.last_checked_appointment_id = int(row[0])
                    logger.info(f"Database Monitor initialized. Last seen appointment ID: {self.last_checked_appointment_id}")
            conn.close()
        except Exception as e:
            logger.error(f"Failed to initialize database monitor: {e}")

    def get_db_stats(self) -> Dict[str, int]:
        """
        Queries and returns diagnostic counts for system stats command.
        """
        stats = {"users": 0, "patients": 0, "appointments": 0}
        if not os.path.exists(self.db_path):
            return stats
            
        try:
            conn = self.get_db_connection()
            cursor = conn.cursor()
            
            # Helper to safely run counts
            tables = ["users", "patients", "appointments"]
            for table in tables:
                cursor.execute(f"SELECT name FROM sqlite_master WHERE type='table' AND name='{table}'")
                if cursor.fetchone():
                    cursor.execute(f"SELECT COUNT(*) FROM {table}")
                    stats[table] = cursor.fetchone()[0]
                    
            conn.close()
        except Exception as e:
            logger.error(f"Error querying database stats: {e}")
            
        return stats

    def create_in_app_notification(self, title: str, body: str, notification_type: str = "warning"):
        """
        Inserts a clinic notification entry directly into clinic.db notifications table.
        """
        if not os.path.exists(self.db_path):
            return
            
        try:
            conn = self.get_db_connection()
            cursor = conn.cursor()
            # Ensure notifications table exists
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='notifications'")
            if cursor.fetchone():
                created_at = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S.%f")
                cursor.execute("""
                    INSERT INTO notifications (title, body, type, read, created_at)
                    VALUES (?, ?, ?, 0, ?)
                """, (title, body, notification_type, created_at))
                conn.commit()
                logger.info(f"Created in-app notification: '{title}'")
            conn.close()
        except Exception as e:
            logger.error(f"Failed to insert in-app notification: {e}")

    def poll_for_urgent_appointments(self):
        """
        Scans for new appointments with ID greater than last seen, filters for
        'Urgent' types, and triggers email notifications and system-wide alerts.
        """
        if not os.path.exists(self.db_path):
            return

        try:
            conn = self.get_db_connection()
            cursor = conn.cursor()
            
            # Check table existence
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='appointments'")
            if not cursor.fetchone():
                conn.close()
                return

            cursor.execute("""
                SELECT a.id, a.type, a.date, a.time, a.condition, p.name, p.phone
                FROM appointments a
                JOIN patients p ON a.patient_id = p.id
                WHERE a.id > ?
                ORDER BY a.id ASC
            """, (self.last_checked_appointment_id,))
            
            new_rows = cursor.fetchall()
            
            max_id = self.last_checked_appointment_id
            for row in new_rows:
                appt_id, appt_type, appt_date, appt_time, appt_cond, pat_name, pat_phone = row
                max_id = max(max_id, appt_id)

                # Process if it is urgent
                if appt_type and appt_type.strip().lower() == "urgent":
                    alert_title = "🚨 URGENT Appointment Booked"
                    alert_body = f"Patient: {pat_name} has booked an urgent slot for {appt_cond} on {appt_date} at {appt_time}."
                    
                    logger.info(f"Database Monitor: Detected new urgent appointment ID {appt_id} for {pat_name}")
                    
                    # 1. Log event
                    logger.warning(f"URGENT BOOKING EVENT: {alert_body}")
                    
                    # 2. Insert in-app notifications
                    self.create_in_app_notification(alert_title, alert_body, "urgent")
                    
                    # 3. Notify Admin / Team via EmailService
                    if self.email_svc.auth.email_user:
                        self.email_svc.send_email(
                            to_email=self.email_svc.auth.email_user,
                            subject=f"[Clinic Alert] Urgent Booking: {pat_name}",
                            plain_body=alert_body
                        )

            self.last_checked_appointment_id = max_id
            conn.close()
        except Exception as e:
            logger.error(f"Error querying database changes during polling: {e}")


# ─── AUTONOMOUS WORKER RUNNER ───────────────────────────────────────────────

class ClinicAutomationSystem:
    """
    Orchestrates the background worker loops, polling intervals, test executions,
    and safe lifecycle controls.
    """
    def __init__(self, test_mode: bool = False):
        self.test_mode = test_mode
        self.email_svc = EmailService(auth_mgr, test_mode=self.test_mode)
        self.git_sync = GitHubSync(auth_mgr)
        self.db_monitor = DatabaseMonitor(DB_FILE_PATH, self.email_svc)
        self.running = False

    def handle_email_command(self, cmd_data: Dict[str, Any]):
        """
        Dispatches parsed inbox email commands.
        """
        sender = cmd_data.get("sender", "")
        command = cmd_data.get("command", "").strip().upper()
        body = cmd_data.get("body", "")
        
        logger.info(f"Executing command '{command}' requested by {sender}")
        
        # Parse command email address
        clean_sender_match = re.search(r"[\w\.-]+@[\w\.-]+\.\w+", sender)
        sender_email = clean_sender_match.group(0) if clean_sender_match else self.email_svc.auth.email_user

        if command == "STATUS":
            stats = self.db_monitor.get_db_stats()
            reply_subject = "[Clinic System] Database Health Status Report"
            reply_body = (
                f"Smart Dental Clinic - Automated Status Report\n"
                f"Generated at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
                f"Current Database Stats:\n"
                f" - Registered Clinic Users: {stats['users']}\n"
                f" - Mapped Patient Records: {stats['patients']}\n"
                f" - Scheduled Appointments: {stats['appointments']}\n\n"
                f"All systems operational."
            )
            self.email_svc.send_email(sender_email, reply_subject, reply_body)
            logger.info(f"STATUS report sent back to {sender_email}")

        elif command == "ALERT":
            alert_title = "⚠️ Clinic Admin Alert Command Received"
            alert_body = f"Custom alert body submitted via command email:\n{body}"
            
            # Create system notifications
            self.db_monitor.create_in_app_notification(alert_title, alert_body, "warning")
            
            # Reply confirmation
            reply_subject = "[Clinic System] Alert Triggered Successfully"
            reply_body = f"An alert notifications thread has been created inside the app database:\n\n{alert_body}"
            self.email_svc.send_email(sender_email, reply_subject, reply_body)
            logger.info(f"ALERT confirmation sent back to {sender_email}")

        else:
            # Unknown command response
            reply_subject = "[Clinic System] Unknown Command Error"
            reply_body = f"The requested command '{command}' is not supported. Supported commands: STATUS, ALERT."
            self.email_svc.send_email(sender_email, reply_subject, reply_body)
            logger.warning(f"Unknown command '{command}' requested by {sender_email}")

    def run_once(self):
        """
        Executes a single workflow cycle (useful for tests or short-run intervals).
        """
        logger.info("--- Starting Automation Cycle ---")
        
        # 1. Check database for urgent appointments
        self.db_monitor.poll_for_urgent_appointments()
        
        # 2. Check inbox for command emails
        commands = self.email_svc.poll_inbox_commands()
        for cmd in commands:
            try:
                self.handle_email_command(cmd)
            except Exception as e:
                logger.error(f"Failed to execute command '{cmd.get('command')}': {e}")
                
        # 3. Perform Git Sync check
        self.git_sync.commit_and_push()
        
        logger.info("--- Automation Cycle Completed ---")

    def start(self, interval_seconds: int = 30):
        """
        Starts the background loop with configurable polling frequency.
        """
        logger.info(f"Starting Clinic Automation System. Polling interval: {interval_seconds} seconds.")
        
        if not auth_mgr.validate_credentials():
            logger.warning("Auth validation failed. App credentials/tokens are missing. Connect functions will fail safely.")

        self.running = True
        try:
            while self.running:
                try:
                    self.run_once()
                except Exception as e:
                    logger.error(f"Error during automation runner execution cycle: {e}")
                
                # Sleep between loops
                time.sleep(interval_seconds)
        except KeyboardInterrupt:
            logger.info("Shutdown signal received. Stopping Automation System...")
        finally:
            self.running = False


# ─── ENTRYPOINT ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Smart Dental Clinic Automation Background Service")
    parser.add_argument(
        "--test",
        action="store_true",
        help="Run in test verification mode (mocks external service SMTP/IMAP connections)"
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=30,
        help="Polling interval loop frequency in seconds (default: 30)"
    )
    
    args = parser.parse_args()

    print("==================================================")
    print("      SMART DENTAL CLINIC AUTOMATION SYSTEM")
    print("==================================================")
    print(f"Log Output Path: {LOG_FILE_PATH}")
    print(f"Database Source: {DB_FILE_PATH}")
    print(f"Test Mode Active: {args.test}")
    print("==================================================\n")

    system = ClinicAutomationSystem(test_mode=args.test)
    
    if args.test:
        logger.info("Running in CLI Test Verification Mode...")
        
        # Perform Git status check
        git_status = system.git_sync.check_status()
        logger.info(f"Git Status output checked successfully. Modified files:\n{git_status or 'None (Working tree clean)'}")
        
        # Run one loop cycle
        system.run_once()
        
        logger.info("Test Mode Completed. CLI verification checks succeeded!")
    else:
        system.start(interval_seconds=args.interval)


if __name__ == "__main__":
    main()
