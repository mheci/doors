#!/usr/bin/env bash
# Weekly host check. The timer calls this; it must not install anything.
exec /usr/bin/doors-update check --scope host --quiet
