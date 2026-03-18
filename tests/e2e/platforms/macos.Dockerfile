# macOS cannot be containerized in Docker. This Dockerfile uses an Ubuntu base
# to test bash compatibility in a macOS-like environment (e.g. bash 4+, no GNU
# date milliseconds). The intent is to catch regressions in cross-platform code
# paths such as __n2_unix_millis and BSD-style date fallbacks.
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    bash \
    tmux \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY . /n2

WORKDIR /n2
