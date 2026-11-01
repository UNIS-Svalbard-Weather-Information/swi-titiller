# Stage 1: Dependency resolution
FROM astral/uv:python3.13-bookworm-slim AS uv
WORKDIR /swi
COPY pyproject.toml uv.lock ./
# Export the locked, hashed set: the image installs exactly what uv.lock pins.
RUN uv export --frozen --no-dev --no-emit-project -o requirements.txt

# Stage 2: Build
FROM python:3.15-slim AS builder
WORKDIR /swi
# Install system dependencies
RUN apt-get update && apt-get install -y libexpat1 && rm -rf /var/lib/apt/lists/*
COPY --from=uv /swi/requirements.txt .
RUN pip install --no-cache-dir --require-hashes -r requirements.txt

# Stage 3: Runtime
FROM python:3.15-slim
# The project reserves uids above 9000. Every SWI image that shares a volume with this one
# (the cron job that writes the forecast data) uses the same uid and gid, so the files this
# service reads and the user it runs as always match.
ARG APP_UID=9001
ARG APP_GID=9001
WORKDIR /swi
# Install system dependencies (curl is needed for the HEALTHCHECK below)
RUN apt-get update && apt-get install -y --no-install-recommends libexpat1 curl && rm -rf /var/lib/apt/lists/*
# Copy only necessary files from the builder stage
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
# The service never installs packages at runtime: remove pip (and its vendored copies
# of urllib3, msgpack, ...) so they are neither exposed nor flagged by image scanners.
RUN python -m pip uninstall -y pip setuptools wheel 2>/dev/null || true
# Unprivileged user
RUN groupadd --gid "${APP_GID}" swi \
    && useradd --uid "${APP_UID}" --gid "${APP_GID}" --create-home --shell /usr/sbin/nologin swi
# The service only reads the forecast volume (mounted read-only). Create the mount point
# owned by the service user: an empty named volume inherits the ownership of the directory
# it is mounted on, so whichever container mounts a fresh volume first, it ends up owned by
# the same uid as the cron job that writes it.
RUN mkdir -p /swi/data/forecast && chown -R swi:swi /swi/data
# Copy application code (owned by root: the service cannot modify its own code)
COPY . .
# Environment variables
ENV PORT=8000
ENV WORKERS=4
# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8085/health || exit 1
# Expose the port
EXPOSE 8085
USER swi
# Run the app
ENV API_ROOT_PATH="/tiles/"
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port 8085 --workers 4 --root-path $API_ROOT_PATH"]
