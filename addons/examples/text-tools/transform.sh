set -euo pipefail
request=$(cat)
text=$(printf '%s' "$request" | /usr/bin/plutil -extract inputs.text raw -n -o - -; printf '\001')
text=${text%$'\001'}
mode=$(printf '%s' "$request" | /usr/bin/plutil -extract inputs.mode raw -o - -)
case "$mode" in
  UPPERCASE) printf '%s' "$text" | /usr/bin/tr '[:lower:]' '[:upper:]' ;;
  lowercase) printf '%s' "$text" | /usr/bin/tr '[:upper:]' '[:lower:]' ;;
  'Count characters') printf '%s' "$text" | /usr/bin/wc -m | /usr/bin/xargs printf 'Characters: %s\n' ;;
  *) printf 'Unknown transformation\n' >&2; exit 1 ;;
esac
