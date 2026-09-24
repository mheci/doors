# Native CUDA Toolkit 13.4 installed from the reviewed NVIDIA Fedora 44 route.
# The RPM payload is relocated under immutable /usr because Atomic Fedora maps
# /usr/local to mutable /var/usrlocal. The NVIDIA Open base owns the driver.
#
# Library search paths are registered through /etc/ld.so.conf.d rather than a
# global LD_LIBRARY_PATH export, which would otherwise be inherited by every
# process in the session and let a writable prefix shadow trusted libraries.
if [[ -d /usr/lib/doors/cuda-13.4 ]]; then
  export CUDA_HOME=/usr/lib/doors/cuda-13.4
  export CUDA_PATH="${CUDA_HOME}"
  export PATH="${CUDA_HOME}/bin:${PATH}"
fi
