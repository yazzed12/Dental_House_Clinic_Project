from __future__ import annotations

from decimal import Decimal

from datetime import datetime

from pydantic import BaseModel, Field, field_validator


def validate_positive_money(value: Decimal) -> Decimal:
    if not value.is_finite() or value <= 0 or value.as_tuple().exponent < -2:
        raise ValueError("Amount must be positive with at most two decimals")
    return value


class ProcedureCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    price: Decimal

    @field_validator("price")
    @classmethod
    def validate_price(cls, value: Decimal) -> Decimal:
        if not value.is_finite() or value < 0 or value.as_tuple().exponent < -2:
            raise ValueError("Price must be a non-negative amount with at most two decimals")
        return value


class ProcedureUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    price: Decimal | None = None
    is_active: bool | None = None

    @field_validator("price")
    @classmethod
    def validate_price(cls, value: Decimal | None) -> Decimal | None:
        if value is not None and (
            not value.is_finite() or value < 0 or value.as_tuple().exponent < -2
        ):
            raise ValueError("Price must be a non-negative amount with at most two decimals")
        return value


class ConsultationProcedureSelection(BaseModel):
    procedureId: str
    quantity: int = Field(ge=1, le=999)


class ConsultationProceduresSave(BaseModel):
    version: int = Field(ge=0)
    selections: list[ConsultationProcedureSelection]


class PaymentCreate(BaseModel):
    billingVersion: int = Field(ge=0)
    amount: Decimal
    paidAt: datetime

    @field_validator("amount")
    @classmethod
    def validate_amount(cls, value: Decimal) -> Decimal:
        return validate_positive_money(value)


class PaymentCorrection(BaseModel):
    billingVersion: int = Field(ge=0)
    expectedRevision: int = Field(ge=1)
    amount: Decimal
    paidAt: datetime
    reason: str = Field(min_length=1, max_length=500)

    @field_validator("amount")
    @classmethod
    def validate_amount(cls, value: Decimal) -> Decimal:
        return validate_positive_money(value)

    @field_validator("reason")
    @classmethod
    def validate_reason(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Correction reason is required")
        return value
