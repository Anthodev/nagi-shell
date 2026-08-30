#!/usr/bin/env bash
set -euo pipefail

operation=$1
if [[ $operation == write ]]; then
    exit 1
fi
exec "${NAGI_REAL_SETTINGS_HELPER:?}" "$@"
