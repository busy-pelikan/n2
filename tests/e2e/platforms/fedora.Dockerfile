FROM fedora:latest

RUN dnf install -y \
    bash \
    tmux \
    git \
    && dnf clean all

COPY . /n2

WORKDIR /n2
