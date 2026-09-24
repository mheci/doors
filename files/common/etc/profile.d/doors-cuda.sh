# Native CUDA Toolkit 13.4 installed from the reviewed NVIDIA Fedora 44 route.
# The normal driver/userspace remains owned by the NVIDIA Open base image.
if [[ -d /usr/local/cuda-13.4 ]]; then
  export CUDA_HOME=/usr/local/cuda-13.4
  export PATH="${CUDA_HOME}/bin:${PATH}"
  export LD_LIBRARY_PATH="${CUDA_HOME}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi
