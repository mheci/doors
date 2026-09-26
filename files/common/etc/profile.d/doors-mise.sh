# Expose per-user mise-managed tools (OpenCode, Pi, Codex, Herdr) in login
# shells. Shims are used rather than shell activation so the same PATH works
# for non-interactive shells and for tools that spawn subprocesses.
case ":${PATH}:" in
  *":${HOME}/.local/share/mise/shims:"*) ;;
  *) PATH="${HOME}/.local/share/mise/shims:${PATH}" ;;
esac
export PATH
