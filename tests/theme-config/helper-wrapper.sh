#!/usr/bin/env bash
set -euo pipefail

operation=$1
if [[ $operation == serve ]]; then
    while IFS= read -r line; do
        request=${line%% *}
        if [[ $request == write ]]; then
            printf 'ERR\n'
        else
            printf 'ERR\n'
        fi
    done
    exit 0
fi
exec "${NAGI_REAL_SETTINGS_HELPER:?}" "$@"
