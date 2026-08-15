from typing import List, Optional

from sqlalchemy.orm import Session

import models


class ReportRepository:
    """Persistence adapter for the active root-model SQLAlchemy universe."""

    def get_by_id(self, db: Session, report_id) -> Optional[models.ClinicalReport]:
        rid = str(report_id)
        return db.query(models.ClinicalReport).filter(
            (models.ClinicalReport.id == rid)
            | (models.ClinicalReport.id == report_id)
        ).first()

    def get_by_patient_id(
        self, db: Session, patient_id
    ) -> List[models.ClinicalReport]:
        pid = str(patient_id)
        return db.query(models.ClinicalReport).filter(
            (models.ClinicalReport.patient_id == pid)
            | (models.ClinicalReport.patient_id == patient_id)
        ).order_by(models.ClinicalReport.created_at.desc()).all()

    @staticmethod
    def add(db: Session, report: models.ClinicalReport) -> None:
        db.add(report)

    @staticmethod
    def commit(db: Session, report: models.ClinicalReport) -> models.ClinicalReport:
        db.commit()
        db.refresh(report)
        return report
