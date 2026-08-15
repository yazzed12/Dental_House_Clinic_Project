from fastapi import Depends, HTTPException


CATALOG_READ = "finance.catalog.read"
CATALOG_MANAGE = "finance.catalog.manage"
BILLING_READ = "finance.billing.read"
BILLING_WRITE = "finance.billing.write"
PAYMENT_READ = "finance.payment.read"
PAYMENT_RECORD = "finance.payment.record"
PAYMENT_CORRECT = "finance.payment.correct"
PATIENT_HISTORY_READ = "finance.patient_history.read"

DOCTOR_CAPABILITIES = frozenset({
    CATALOG_READ, CATALOG_MANAGE, BILLING_READ, BILLING_WRITE,
    PAYMENT_READ, PAYMENT_RECORD, PAYMENT_CORRECT, PATIENT_HISTORY_READ,
})

ROLE_CAPABILITIES = {"doctor": DOCTOR_CAPABILITIES}


def require_finance_capability(capability, authenticated_dependency):
    def dependency(user=Depends(authenticated_dependency)):
        if capability not in ROLE_CAPABILITIES.get(user.role, frozenset()):
            raise HTTPException(status_code=403, detail="Insufficient financial permissions")
        return user
    return dependency
