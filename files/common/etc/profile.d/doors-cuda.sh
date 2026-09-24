# Native CUDA Toolkit 13.4 installed from the reviewed NVIDIA Fedora 44 route.
# The RPM payload is relocated under immutable /usr because Atomic Fedora maps
# /usr/local to mutable /var/usrlocal. The NVIDIA Open base owns the driver.
if [[ -d /usr/lib/doors/cuda-13.4 ]]; then
  export CUDA_HOME=/usr/lib/doors/cuda-13.4
  export PATH="${CUDA_HOME}/bin:${PATH}"
  export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${CUDA_HOME}/targets/x86_64-linux/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi
