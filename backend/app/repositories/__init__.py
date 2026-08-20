from importlib import import_module

__all__ = [
    "UserRepository",
    "PatientRepository",
    "AppointmentRepository",
    "ConsultationRepository",
    "ReportRepository",
    "NotificationRepository",
    "SymptomRepository",
    "ClinicSettingsRepository",
    "RecordRepository",
    "LogRepository",
    "AppointmentConditionRepository",
    "CommonRepository",
    "MedicationRepository",
]

_REPOSITORY_MODULES = {
    "UserRepository": "user_repository",
    "PatientRepository": "patient_repository",
    "AppointmentRepository": "appointment_repository",
    "ConsultationRepository": "consultation_repository",
    "ReportRepository": "report_repository",
    "NotificationRepository": "notification_repository",
    "SymptomRepository": "symptom_repository",
    "ClinicSettingsRepository": "clinic_settings_repository",
    "RecordRepository": "record_repository",
    "LogRepository": "log_repository",
    "AppointmentConditionRepository": "appointment_condition_repo",
    "CommonRepository": "common_repository",
    "MedicationRepository": "medication_repository",
}


def __getattr__(name):
    module_name = _REPOSITORY_MODULES.get(name)
    if module_name is None:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    repository = getattr(import_module(f"{__name__}.{module_name}"), name)
    globals()[name] = repository
    return repository
