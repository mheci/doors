# Doors — local LLM (llama.cpp)
alias llm := server

# Start llama-server (GPU offload via the image's CUDA/HIP build)
server model prompt="Talk to me." ctx="8192":
    #!/usr/bin/env bash
    set -euo pipefail
    llama-server -m "{{model}}" -c {{ctx}} --host 127.0.0.1 --port 8080

# One-shot completion
ask model prompt:
    llama-cli -m "{{model}}" -p "{{prompt}}"

# Benchmark a model
bench model:
    llama-bench -m "{{model}}"

# Quantize a GGUF (q4_k_m by default)
quantize in out type="q4_k_m":
    llama-quantize "{{in}}" "{{out}}" {{type}}
