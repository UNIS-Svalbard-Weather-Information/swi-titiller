from urllib.parse import urlparse

from typing import Annotated
from titiler.core.factory import TilerFactory
from titiler.core.errors import DEFAULT_STATUS_CODES, add_exception_handlers

from fastapi import FastAPI, Query, HTTPException

import os


def DatasetPathParams(url: Annotated[str, Query(description="Dataset URL")]) -> str:
    """Sanitize and validate local COG paths for TiTiler, preventing directory traversal."""
    # Reject remote URLs if not needed (or validate host if needed)
    if url.startswith(("http://", "https://")):
        raise HTTPException(
            status_code=400,
            detail="Remote URLs are not allowed. Only local paths are supported.",
        )

    # Only allow paths starting with 'data/'
    if not url.startswith("data/"):
        raise HTTPException(
            status_code=400,
            detail="Invalid path. Only paths starting with 'data/' are allowed.",
        )

    # Normalize the path to resolve any '..' or '.'
    normalized_path = os.path.normpath(url)

    # Ensure the normalized path still starts with 'data' and does not escape
    if (
        not normalized_path.startswith("data")
        or ".." in normalized_path
        or normalized_path.startswith("/")
    ):
        raise HTTPException(
            status_code=400,
            detail="Invalid path. Path traversal or absolute paths are not allowed.",
        )

    return f"file:///swi/{url}"


app = FastAPI(title="SWI Titiller API")
app.include_router(
    TilerFactory(path_dependency=DatasetPathParams).router,
    tags=["Cloud Optimized GeoTIFF"],
)

add_exception_handlers(app, DEFAULT_STATUS_CODES)
