#!/usr/bin/env bash
# Copyright (C) 2026 Michael A Jones.  GPL-3.0-or-later; see LICENSE.
# Make build/facematch-x86_64.AppImage: the facematch engine with all it
# needs in one file, nothing installed: a relocatable Python
# (python-build-standalone), InsightFace with its dependencies, ONNX Runtime
# and OpenCV, the models (YuNet from OpenCV Zoo, MIT; AuraFace-v1's
# glintr100.onnx from fal, Apache 2.0) with their licences, and
# calibration.json. Built in an Ubuntu 24.04 podman container, so that it
# runs where glibc is 2.39 or later.
#
# Every download is pinned: the files by their SHA-256, the models by the
# commit of the repository they come from as well, the Python packages by
# the hashes in requirements.txt. A download that is not the file expected
# is not used. What is downloaded is kept in build/cache/ for the next
# build; the container is named after requirements.txt, so a changed lock
# is built in a new one.
#
# Usage: ./build-appimage.sh          the AppImage (calibration.json must exist)
#        ./build-appimage.sh --env    only the container's Python with its
#                                     packages and the models, for calibrate.py
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
build="$here/build"
cache="$build/cache"
mkdir -p "$cache/models"
image=docker.io/library/ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac
container="facematch-build-$(sha256sum "$here/requirements.txt" | cut -c1-12)"

python_url=https://github.com/astral-sh/python-build-standalone/releases/download/20241016/cpython-3.12.7+20241016-x86_64-unknown-linux-gnu-install_only.tar.gz
python_sha256=43576f7db1033dd57b900307f09c2e86f371152ac8a2607133afa51cbfc36064
yunet_commit=48b10fa505aeb51fbd127fc60a5c660040e823b7
yunet_url=https://github.com/opencv/opencv_zoo/raw/$yunet_commit/models/face_detection_yunet/face_detection_yunet_2023mar.onnx
yunet_sha256=8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
yunet_licence_url=https://raw.githubusercontent.com/opencv/opencv_zoo/$yunet_commit/models/face_detection_yunet/LICENSE
yunet_licence_sha256=c83b8120c50ccbd4c4f96edf53141bdd566ebb8f8e9227e415326aa1b1aba958
auraface=https://huggingface.co/fal/AuraFace-v1/resolve/af6d057c9b0ec4071d4c49c80e3539258798b609
auraface_sha256=a7933ea5330113b01c9b60351d8f4c33003f145d8470ac5f0e52ee2effe25c60
auraface_licence_sha256=609e2cb599f84aaa41d8ef29d8fdb04d164fab22e8d9292ca34a599d0f56a338
appimagetool_url=https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
appimagetool_sha256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
runtime_url=https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64
runtime_sha256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d

fetch() {  # download $1 to $2 unless it is there with SHA-256 $3; a download that differs is not kept
  if ! echo "$3  $2" | sha256sum -c --status 2>/dev/null; then
    curl -sSfL -o "$2.part" "$1"
    if ! echo "$3  $2.part" | sha256sum -c --status; then
      rm -f "$2.part"
      echo "$1 is not the file expected: not used" >&2
      exit 1
    fi
    mv "$2.part" "$2"
  fi
}
fetch "$python_url" "$cache/python.tar.gz" "$python_sha256"
fetch "$yunet_url" "$cache/models/face_detection_yunet_2023mar.onnx" "$yunet_sha256"
fetch "$yunet_licence_url" "$cache/models/LICENSE-YuNet" "$yunet_licence_sha256"
fetch "$auraface/glintr100.onnx" "$cache/models/glintr100.onnx" "$auraface_sha256"
fetch "$auraface/LICENSE.md" "$cache/models/LICENSE-AuraFace.md" "$auraface_licence_sha256"
fetch "$appimagetool_url" "$cache/appimagetool-x86_64.AppImage" "$appimagetool_sha256"
fetch "$runtime_url" "$cache/runtime-x86_64" "$runtime_sha256"
chmod +x "$cache/appimagetool-x86_64.AppImage"

if ! podman container exists "$container"; then
  podman run -d --name "$container" -v "$cache:/cache:z" "$image" sleep infinity >/dev/null
  podman exec "$container" sh -c 'DEBIAN_FRONTEND=noninteractive apt-get update -qq &&
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential >/dev/null'
fi
podman start "$container" >/dev/null
# stopped when the build ends, however it ends; --env leaves it running for calibrate.py
[ "${1:-}" = --env ] || trap 'podman stop -t 0 "$container" >/dev/null 2>&1 || true' EXIT
podman cp "$here/requirements.txt" "$container:/tmp/requirements.txt"
# the Python and its packages, made once: InsightFace builds its C parts here
podman exec "$container" bash -c '
  set -e
  if [ ! -x /opt/AppDir/usr/python/bin/python3 ]; then
    mkdir -p /opt/AppDir/usr
    tar -xzf /cache/python.tar.gz -C /opt/AppDir/usr
  fi
  py=/opt/AppDir/usr/python/bin/python3
  export NO_ALBUMENTATIONS_UPDATE=1 PIP_DISABLE_PIP_VERSION_CHECK=1
  if ! $py -c "import insightface" 2>/dev/null; then
    # every package but InsightFace first, among them what it is built with
    awk "/^insightface==/ {skip=1; next} /^[^ ]/ {skip=0} !skip" /tmp/requirements.txt > /tmp/without-insightface.txt
    awk "/^insightface==/ {take=1; print; next} /^[^ ]/ {take=0} take" /tmp/requirements.txt > /tmp/insightface.txt
    $py -m pip install -q --no-cache-dir --require-hashes --no-deps -r /tmp/without-insightface.txt
    # InsightFace compiled with the system compiler, against the numpy just installed
    CC=gcc CXX=g++ $py -m pip install -q --no-cache-dir --require-hashes --no-deps --no-build-isolation -r /tmp/insightface.txt
  fi
  $py -m pip check >/dev/null
  $py -c "import insightface, onnxruntime, cv2, numpy"'
[ "${1:-}" = --env ] && { echo "the engine Python is ready in the container $container, at /opt/AppDir/usr/python"; exit 0; }

[ -s "$here/calibration.json" ] || { echo "no calibration.json: run calibrate.py first (see README.md)" >&2; exit 1; }
# the engine copied in afresh each build, never read through a mount
podman exec "$container" rm -rf /engine-now
podman exec "$container" mkdir /engine-now
podman cp "$here/facematch.py" "$container:/engine-now/facematch.py"
podman cp "$here/calibration.json" "$container:/engine-now/calibration.json"
podman exec "$container" bash -c '
  set -e
  app=/opt/AppDir
  mkdir -p $app/usr/share/facematch/models $app/usr/share/facematch/licenses
  cp /engine-now/facematch.py $app/usr/share/facematch/
  cp /engine-now/calibration.json /cache/models/face_detection_yunet_2023mar.onnx /cache/models/glintr100.onnx $app/usr/share/facematch/models/
  cp /cache/models/LICENSE-YuNet /cache/models/LICENSE-AuraFace.md $app/usr/share/facematch/licenses/
  cat > $app/AppRun <<"EOF"
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
export APPDIR="$here" NO_ALBUMENTATIONS_UPDATE=1 OMP_NUM_THREADS=4 MALLOC_ARENA_MAX=2
exec "$here/usr/python/bin/python3" -I -s -W ignore::FutureWarning "$here/usr/share/facematch/facematch.py" "$@"
EOF
  chmod +x $app/AppRun
  printf "[Desktop Entry]\nType=Application\nName=facematch\nExec=facematch\nIcon=facematch\nTerminal=true\nCategories=Utility;\n" > $app/facematch.desktop
  rm -rf /tmp/AppDir && cp -a $app /tmp/AppDir'
rm -rf "$build/AppDir"
podman cp "$container:/tmp/AppDir" "$build/AppDir"
cp "$here/LICENSE" "$build/AppDir/usr/share/facematch/licenses/LICENSE-facematch"
cp "$here/facematch.png" "$build/AppDir/facematch.png"
ARCH=x86_64 "$cache/appimagetool-x86_64.AppImage" --appimage-extract-and-run --no-appstream \
  --runtime-file "$cache/runtime-x86_64" "$build/AppDir" "$build/facematch-x86_64.AppImage" >/dev/null
echo "$build/facematch-x86_64.AppImage"
