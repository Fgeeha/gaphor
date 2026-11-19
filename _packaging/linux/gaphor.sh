#!/bin/sh
# Launcher for the Gaphor installation in /opt/gaphor
if [ -d /opt/gaphor/lib/girepository-1.0 ]; then
    # Private libadwaita build (RED OS)
    export LD_LIBRARY_PATH="/opt/gaphor/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export GI_TYPELIB_PATH="/opt/gaphor/lib/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
fi
exec /opt/gaphor/bin/gaphor "$@"
