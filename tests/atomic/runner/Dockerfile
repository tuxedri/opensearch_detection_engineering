FROM python:3.12.10-slim-bookworm

RUN apt-get update \
    && apt-get install --yes --no-install-recommends bash coreutils \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir PyYAML==6.0.2

WORKDIR /lab
