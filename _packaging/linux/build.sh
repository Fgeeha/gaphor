#!/bin/bash
# Build a self-contained Gaphor installation in /opt/gaphor and package it
# as .deb (Ubuntu) or .rpm (RED OS).
#
# Run as root inside a container of the target distribution:
#
#   docker run --rm -v "$PWD:/src:ro" -v "$PWD/dist:/out" -e VERSION=3.4.0 \
#       ubuntu:26.04 /src/_packaging/linux/build.sh
#
# The application is installed in a virtual environment, linked against the
# system GTK stack. If the distribution ships a libadwaita that is too old,
# a private copy is built and installed under /opt/gaphor as well.
set -euo pipefail

: "${VERSION:?VERSION must be set, e.g. 3.4.0 or 3.4.0.dev12+abcdef12}"
SRC=${SRC:-/src}
OUT=${OUT:-/out}
PREFIX=/opt/gaphor
STAGE=/tmp/stage
BUILD=/tmp/build

GTK_VERSION=4.20.4
GTK_SHA256=a21f825bd44afc4dd99ba4eea8ff57c8f2e51085cb402a68ed4cbb35299826a4
ADW_VERSION=1.8.8
ADW_SHA256=9e64939959a071cb660090c0e1b380c51ca29e3cfb57f3f23ea42a9922eb6f41
NFPM_VERSION=2.49.0
NFPM_SHA256=2afaa5ffb5e3493402e31e7c67a5a1fb42133e3f66fc315ca0051934125561c7

# Read in a subshell: os-release defines VERSION too
# shellcheck source=/dev/null
OS_ID=$(. /etc/os-release && echo "$ID")
# shellcheck source=/dev/null
OS_VERSION=$(. /etc/os-release && echo "$VERSION_ID")
case "$OS_ID" in
ubuntu | debian)
    export DEBIAN_FRONTEND=noninteractive
    FORMAT=deb
    DIST=$OS_ID-$OS_VERSION
    PYTHON=python3
    BUILD_GTK=false
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        ca-certificates curl gcc pkg-config python3-dev python3-venv \
        libcairo2-dev libgirepository-2.0-dev \
        gir1.2-gtk-4.0 gir1.2-adw-1 gir1.2-gtksource-5
    ;;
redos)
    FORMAT=rpm
    DIST=$OS_ID-${OS_VERSION%%.*}
    PYTHON=python3.13
    BUILD_GTK=true
    dnf install -y -q \
        curl gcc pkgconf tar xz python3.13 python3.13-devel \
        cairo-devel cairo-gobject-devel gobject-introspection-devel \
        gtk4 gtksourceview5 \
        meson ninja-build sassc glib2-devel pango-devel harfbuzz-devel \
        gdk-pixbuf2-devel librsvg2-devel graphene-devel libepoxy-devel fribidi-devel \
        libpng-devel libjpeg-turbo-devel libtiff-devel libdrm-devel \
        wayland-devel wayland-protocols-devel libxkbcommon-devel \
        libX11-devel libXi-devel libXrandr-devel libXcursor-devel \
        libXdamage-devel libXinerama-devel libXext-devel libXfixes-devel \
        iso-codes-devel cups-devel appstream-devel
    ;;
*)
    echo "Unsupported distribution: $OS_ID" >&2
    exit 1
    ;;
esac

mkdir -p "$BUILD" "$OUT"
cp -a "$SRC/." "$BUILD/gaphor"
cd "$BUILD/gaphor"

# Package version: 3.4.0.dev12+abcdef12 -> version 3.4.0, prerelease dev12
PKG_VERSION=${VERSION%%.dev*}
PKG_PRERELEASE=""
if [[ "$VERSION" == *.dev* ]]; then
    PKG_PRERELEASE=dev${VERSION#*.dev}
    PKG_PRERELEASE=${PKG_PRERELEASE%%+*}
fi
export PKG_VERSION PKG_PRERELEASE

# Download a GNOME source tarball, verify it and build it into $PREFIX
build_gnome() {
    local name=$1 version=$2 sha256=$3
    shift 3
    curl -fsSL -o "/tmp/$name.tar.xz" \
        "https://download.gnome.org/sources/$name/${version%.*}/$name-$version.tar.xz"
    echo "$sha256  /tmp/$name.tar.xz" | sha256sum -c -
    tar -xf "/tmp/$name.tar.xz" -C "$BUILD"
    meson setup "$BUILD/$name-build" "$BUILD/$name-$version" \
        --prefix="$PREFIX" --libdir=lib --buildtype=release "$@"
    meson install -C "$BUILD/$name-build"
}

if [ "$BUILD_GTK" = true ]; then
    # The system GTK/libadwaita are too old: ship private copies
    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export LD_LIBRARY_PATH="$PREFIX/lib"
    export GI_TYPELIB_PATH="$PREFIX/lib/girepository-1.0"
    export XDG_DATA_DIRS="$PREFIX/share:/usr/share"
    build_gnome gtk "$GTK_VERSION" "$GTK_SHA256" \
        -Dintrospection=enabled -Dmedia-gstreamer=disabled -Dvulkan=disabled \
        -Dprint-cpdb=disabled -Dcloudproviders=disabled -Dsysprof=disabled \
        -Dcolord=disabled -Daccesskit=disabled -Ddocumentation=false \
        -Dman-pages=false -Dbuild-demos=false -Dbuild-examples=false \
        -Dbuild-tests=false -Dbuild-testsuite=false
    build_gnome libadwaita "$ADW_VERSION" "$ADW_SHA256" \
        -Dintrospection=enabled -Dvapi=false -Dtests=false -Dexamples=false \
        -Ddocumentation=false
    # Keep only runtime files; GSettings schemas come with the system gtk4
    rm -rf "${PREFIX:?}/bin" "$PREFIX/include" "$PREFIX/lib/pkgconfig" \
        "$PREFIX/share/gir-1.0" "$PREFIX/share/glib-2.0" "$PREFIX/share/gettext"
fi

"$PYTHON" -m venv "$PREFIX"
"$PREFIX/bin/pip" install -q --upgrade pip
"$PREFIX/bin/pip" install -q babel
PATH="$PREFIX/bin:$PATH" "$PREFIX/bin/python" -c \
    "from scripts.build_babel import compile_mo_all; compile_mo_all()"
"$PREFIX/bin/pip" install -q --no-cache-dir --no-binary PyGObject,pycairo .
# Force the version, so it is reported correctly by the application
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PREFIX"/lib/python3*/site-packages/gaphor-*.dist-info/METADATA
"$PREFIX/bin/pip" uninstall -q -y pip

# Smoke test: all GTK bindings resolve with the expected versions
"$PREFIX/bin/python" -c "import gaphor.ui; from gi.repository import Adw; print('Adwaita', Adw.MAJOR_VERSION, Adw.MINOR_VERSION)"

# Desktop integration files
install -Dm755 _packaging/linux/gaphor.sh "$STAGE/usr/bin/gaphor"
install -Dm644 data/org.gaphor.Gaphor.desktop "$STAGE/usr/share/applications/org.gaphor.Gaphor.desktop"
install -Dm644 data/org.gaphor.Gaphor.appdata.xml "$STAGE/usr/share/metainfo/org.gaphor.Gaphor.appdata.xml"
install -Dm644 data/org.gaphor.Gaphor.service "$STAGE/usr/share/dbus-1/services/org.gaphor.Gaphor.service"
install -Dm644 data/org.gaphor.Gaphor.xml "$STAGE/usr/share/mime/packages/org.gaphor.Gaphor.xml"
install -Dm644 gaphor/ui/installschemas/org.gaphor.Gaphor.gschema.xml \
    "$STAGE/usr/share/glib-2.0/schemas/org.gaphor.Gaphor.gschema.xml"
install -Dm644 data/logos/org.gaphor.Gaphor.svg \
    "$STAGE/usr/share/icons/hicolor/scalable/apps/org.gaphor.Gaphor.svg"
install -Dm644 data/logos/org.gaphor.Gaphor-symbolic.svg \
    "$STAGE/usr/share/icons/hicolor/symbolic/apps/org.gaphor.Gaphor-symbolic.svg"

curl -fsSL -o /tmp/nfpm.tar.gz \
    "https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VERSION}/nfpm_${NFPM_VERSION}_Linux_x86_64.tar.gz"
echo "$NFPM_SHA256  /tmp/nfpm.tar.gz" | sha256sum -c -
tar -xzf /tmp/nfpm.tar.gz -C /usr/local/bin nfpm

nfpm package --config "_packaging/linux/nfpm.yaml" --packager "$FORMAT" \
    --target "$OUT/gaphor-${VERSION}-${DIST}.x86_64.${FORMAT}"
ls -l "$OUT"
