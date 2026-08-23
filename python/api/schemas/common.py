"""Shared response schemas."""

from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class CamelModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True)


HealthStatus = Literal["healthy", "warning", "critical", "unknown"]


class ComponentHealth(CamelModel):
    name: str
    status: HealthStatus
    detail: Optional[str] = None


class HealthResponse(CamelModel):
    status: HealthStatus
    components: list[ComponentHealth]
    requestId: str
