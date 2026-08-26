#!/usr/bin/env bash
set -euo pipefail

helper=$1
root=$(mktemp -d "${TMPDIR:-/tmp}/nagi-settings-helper.XXXXXX")
trap 'rm -rf "$root"' EXIT
config="$root/config/nagi-shell"
outside="$root/outside.conf"
mkdir -p "$root/config"

inspect=$($helper inspect "$config")
[[ $inspect == *'"settings":"missing"'* ]]
[[ $(stat -c %a "$config") == 700 ]]

content=$'[settings]\nschema_version=2\n'
printf %s "$content" | "$helper" create "$config" "${#content}"
[[ $(stat -c %a "$config/settings.conf") == 600 ]]
[[ $(stat -c %a "$config/settings.conf.last-good") == 600 ]]
cmp -s "$config/settings.conf" "$config/settings.conf.last-good"

printf 'outside\n' > "$outside"
rm "$config/settings.conf"
ln -s "$outside" "$config/settings.conf"
if printf %s "$content" | "$helper" write "$config" "${#content}" 2>/dev/null; then
    echo 'symlink target was accepted' >&2
    exit 1
fi
[[ -L "$config/settings.conf" ]]
[[ $(cat "$outside") == outside ]]
rm "$config/settings.conf"
printf %s "$content" | "$helper" create "$config" "${#content}"

rm "$config/settings.conf.last-good"
ln -s "$outside" "$config/settings.conf.last-good"
next=$'[settings]\nschema_version=2\n\n[clock]\nformat=12h\n'
if printf %s "$next" | "$helper" write "$config" "${#next}" 2>/dev/null; then
    echo 'symlinked last-good target was accepted' >&2
    exit 1
fi
cmp -s "$config/settings.conf" <(printf %s "$content")
[[ $(cat "$outside") == outside ]]
rm -f "$config/settings.conf.last-good"
printf %s "$content" | "$helper" last-good "$config" "${#content}"

rm "$config/settings.conf"
printf '[theme]\nmode=accent\naccent=#123456\n' > "$config/theme.conf"
migrated=$'[settings]\nschema_version=2\n\n[appearance]\naccent_mode=custom\ncustom_accent=#123456\n'
printf %s "$migrated" | "$helper" migrate "$config" "${#migrated}"
[[ ! -e "$config/theme.conf" ]]
cmp -s "$config/settings.conf.bak" <(printf '[theme]\nmode=accent\naccent=#123456\n')
[[ $(stat -c %a "$config/settings.conf.bak") == 600 ]]

printf '[broken\n' > "$config/settings.conf"
printf %s "$content" | "$helper" recover "$config" "${#content}"
cmp -s "$config/settings.conf.invalid" <(printf '[broken\n')
cmp -s "$config/settings.conf" <(printf %s "$content")
chmod 0644 "$config/settings.conf" "$config/settings.conf.last-good"
"$helper" inspect "$config" >/dev/null
[[ $(stat -c %a "$config/settings.conf") == 600 ]]
[[ $(stat -c %a "$config/settings.conf.last-good") == 600 ]]
unsafe_dir="$root/unsafe-directory/nagi-shell"
mkdir -p "$(dirname "$unsafe_dir")"
"$helper" inspect "$unsafe_dir" >/dev/null
mkdir "$unsafe_dir/settings.conf"
if printf %s "$content" | "$helper" write "$unsafe_dir" "${#content}" 2>/dev/null; then
    echo 'directory settings target was accepted' >&2
    exit 1
fi

unsafe_fifo="$root/unsafe-fifo/nagi-shell"
mkdir -p "$(dirname "$unsafe_fifo")"
"$helper" inspect "$unsafe_fifo" >/dev/null
mkfifo "$unsafe_fifo/settings.conf"
if printf %s "$content" | "$helper" write "$unsafe_fifo" "${#content}" 2>/dev/null; then
    echo 'FIFO settings target was accepted' >&2
    exit 1
fi

race="$root/race/nagi-shell"
mkdir -p "$(dirname "$race")"
"$helper" inspect "$race" >/dev/null
set +e
(printf %s "$content" | "$helper" create "$race" "${#content}" >/dev/null 2>&1) &
first=$!
(printf %s "$next" | "$helper" create "$race" "${#next}" >/dev/null 2>&1) &
second=$!
wait "$first"
first_status=$?
wait "$second"
second_status=$?
set -e
[[ $((first_status + second_status)) -eq 1 ]]
cmp -s "$race/settings.conf" "$race/settings.conf.last-good"

echo 'settings helper tests passed'
