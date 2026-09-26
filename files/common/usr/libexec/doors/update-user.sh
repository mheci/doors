#!/usr/bin/env bash
# Weekly per-user check. The timer calls this; it must not install anything.
exec /usr/bin/doors-update check --scope user --quiet
