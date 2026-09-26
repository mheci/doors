#!/usr/bin/env bash
# Build only the audited LADSPA target from a content-addressed Anechoic source
# archive. This module runs in the disposable Doors tools stage; its output is
# copied into the final image without compilers or CMake.
set -euo pipefail

readonly repository='mheci/anechoic'
readonly commit='061038dd98d45abef5fc22ae9c27b289b50b180c'
readonly source_url="https://github.com/${repository}/archive/${commit}.tar.gz"
readonly source_sha256='40bc93f8fa4b99205ecc5a948f4edceb52f9d54098ed5cd62a4ad42372ff9ad4'
readonly output_dir='/out/anechoic'
readonly work_dir='/tmp/doors-anechoic'
readonly source_archive="${work_dir}/anechoic-${commit}.tar.gz"
readonly source_dir="${work_dir}/source"
readonly build_dir="${work_dir}/build"
readonly stage_dir="${work_dir}/stage"

rm -rf "${work_dir}" "${output_dir}"
mkdir -p "${source_dir}" "${output_dir}"

dnf5 install -y --setopt=install_weak_deps=False cmake gcc-c++

curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error \
  --output "${source_archive}" "${source_url}"
echo "${source_sha256}  ${source_archive}" | sha256sum --check --status

tar --extract --file "${source_archive}" --directory "${source_dir}" --strip-components=1
[[ -f "${source_dir}/CMakeLists.txt" && -f "${source_dir}/LICENSE" ]] || {
  echo 'Anechoic source archive has an unexpected layout' >&2
  exit 1
}

# Keep the final payload auditable and deliberately narrow: no tests, offline
# utility, JUCE, VST, VST3, LV2, AU, or AUv3 targets are configured at all.
cmake -S "${source_dir}" -B "${build_dir}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_LIBDIR=lib64 \
  -DBUILD_TESTS=OFF \
  -DBUILD_OFFLINE_TOOL=OFF \
  -DBUILD_LADSPA_PLUGIN=ON \
  -DBUILD_VST_PLUGIN=OFF \
  -DBUILD_VST3_PLUGIN=OFF \
  -DBUILD_LV2_PLUGIN=OFF \
  -DBUILD_AU_PLUGIN=OFF \
  -DBUILD_AUV3_PLUGIN=OFF
cmake --build "${build_dir}" --parallel "$(nproc)" --target anechoic_ladspa
cmake --install "${build_dir}" --prefix "${stage_dir}"

readonly plugin="${stage_dir}/lib64/ladspa/libanechoic_ladspa.so"
[[ -s "${plugin}" ]] || {
  echo 'Anechoic LADSPA build did not produce the expected Fedora lib64 plugin' >&2
  exit 1
}

# Confirm the shared object exposes a LADSPA descriptor before it becomes an
# image artifact. ctypes loads only the just-built local artifact.
python3 - "${plugin}" <<'PY'
import ctypes
import sys

library = ctypes.CDLL(sys.argv[1])
descriptor = library.ladspa_descriptor
descriptor.argtypes = [ctypes.c_ulong]
descriptor.restype = ctypes.c_void_p
if not descriptor(0) or not descriptor(1) or descriptor(2):
    raise SystemExit('unexpected Anechoic LADSPA descriptor inventory')
PY

install -D -m 0755 "${plugin}" "${output_dir}/libanechoic_ladspa.so"
install -D -m 0644 "${source_dir}/LICENSE" "${output_dir}/LICENSE"
install -D -m 0644 "${source_archive}" "${output_dir}/anechoic-${commit}.tar.gz"
cat > "${output_dir}/buildinfo" <<INFO
repository=${repository}
commit=${commit}
source_url=${source_url}
source_sha256=${source_sha256}
license=GPL-3.0
artifacts=libanechoic_ladspa.so,LICENSE,anechoic-${commit}.tar.gz
cmake_options=BUILD_TESTS=OFF,BUILD_OFFLINE_TOOL=OFF,BUILD_LADSPA_PLUGIN=ON,BUILD_VST_PLUGIN=OFF,BUILD_VST3_PLUGIN=OFF,BUILD_LV2_PLUGIN=OFF,BUILD_AU_PLUGIN=OFF,BUILD_AUV3_PLUGIN=OFF
INFO

printf 'Anechoic LADSPA plugin built from %s@%s.\n' "${repository}" "${commit}"
