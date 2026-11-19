#!/bin/sh
# Refresh system caches after Gaphor is installed or removed.
# Debian/Ubuntu triggers do this as well; RED OS may not have file triggers.
command -v glib-compile-schemas >/dev/null && glib-compile-schemas /usr/share/glib-2.0/schemas || :
command -v update-mime-database >/dev/null && update-mime-database /usr/share/mime || :
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || :
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || :
exit 0
