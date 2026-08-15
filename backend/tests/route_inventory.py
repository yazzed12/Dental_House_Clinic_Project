"""Deterministic inventory extraction for the active FastAPI app."""

from __future__ import annotations

from dataclasses import dataclass

from fastapi.routing import APIRoute
from fastapi.security import OAuth2PasswordBearer

from tests.support import active_main


@dataclass(frozen=True, order=True)
class RouteContract:
    method: str
    path: str
    authentication: str
    roles: str


INLINE_ROLE_RESTRICTIONS = {
    ("GET", "/api/settings/clinic"): "admin,doctor",
    ("PUT", "/api/settings/clinic"): "admin,doctor",
}


def _dependency_calls(dependant):
    for dependency in dependant.dependencies:
        call = dependency.call
        if call is not None:
            yield call
        yield from _dependency_calls(dependency)


def _roles_for(call) -> str | None:
    qualname = getattr(call, "__qualname__", "")
    if "require_finance_capability.<locals>.dependency" in qualname:
        return "doctor"
    if "require_staff_role.<locals>.role_checker" in qualname:
        return "admin,doctor,receptionist"
    if "require_role.<locals>.role_checker" in qualname:
        closure = getattr(call, "__closure__", None) or ()
        values = [cell.cell_contents for cell in closure]
        requested = next((value for value in values if isinstance(value, str)), None)
        if requested:
            return "admin" if requested == "admin" else f"admin,{requested}"
    return None


def _application_routes(routes):
    for route in routes:
        if isinstance(route, APIRoute):
            yield route
            continue
        included_router = getattr(route, "original_router", None)
        if included_router is not None:
            yield from _application_routes(included_router.routes)


def active_route_inventory() -> list[RouteContract]:
    inventory: list[RouteContract] = []
    for route in _application_routes(active_main.app.routes):
        calls = list(_dependency_calls(route.dependant))
        authenticated = any(
            call is active_main.get_current_user
            or isinstance(call, OAuth2PasswordBearer)
            for call in calls
        )
        dependency_roles = next(
            (roles for call in calls if (roles := _roles_for(call))), ""
        )
        for method in sorted(route.methods or []):
            roles = INLINE_ROLE_RESTRICTIONS.get((method, route.path), dependency_roles)
            inventory.append(
                RouteContract(
                    method=method,
                    path=route.path,
                    authentication="required" if authenticated else "public",
                    roles=roles,
                )
            )
    return inventory


def to_tsv(inventory: list[RouteContract]) -> str:
    rows = ["method\tpath\tauthentication\troles"]
    rows.extend(
        f"{route.method}\t{route.path}\t{route.authentication}"
        + (f"\t{route.roles}" if route.roles else "")
        for route in inventory
    )
    return "\n".join(rows) + "\n"
