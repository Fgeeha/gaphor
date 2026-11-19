#!/bin/bash
# Install a Gaphor package in a clean container and run the self-test:
#
#   docker run --rm -v "$PWD/dist:/dist:ro" -v "$PWD/_packaging/linux:/scripts:ro" \
#       ubuntu:26.04 /scripts/self-test.sh /dist/gaphor-<version>-ubuntu-26.04.x86_64.deb
set -euo pipefail

PACKAGE=${1:?package file required}

# shellcheck source=/dev/null
. /etc/os-release
case "$ID" in
ubuntu | debian)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq "$PACKAGE" xvfb xauth dbus-daemon
    ;;
redos)
    dnf install -y -q "$PACKAGE" xorg-x11-server-Xvfb dbus-daemon
    ;;
esac

cd /tmp
Xvfb :99 -screen 0 1280x1024x24 &
export DISPLAY=:99 GDK_BACKEND=x11
sleep 2
gaphor --version
# Exit status is non-zero if any of the tests failed
exec dbus-run-session -- gaphor self-test
