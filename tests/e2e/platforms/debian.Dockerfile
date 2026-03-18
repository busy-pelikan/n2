FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    bash \
    tmux \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY . /n2

WORKDIR /n2
