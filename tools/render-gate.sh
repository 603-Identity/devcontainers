#!/usr/bin/env bash
# Renders template/.github/workflows/architect-review-gate.yml.
#
#   tools/render-gate.sh                  write the rendered workflow to stdout
#   tools/render-gate.sh --check [FILE]   exit 1, with a diff, unless FILE (default: the
#                                         template in this repo) is byte-equal to the render
#
# The skeleton is tools/gate-template.yml.in. A line that holds only `@@<name>@@` is replaced
# by tools/<name>, minus its shebang line, indented to match the marker. The scripts carry
# their per-consumer region (the `case` block) as a default; a consuming repo edits that
# region in the rendered template by hand. Output is deterministic: no dates, no env.
set -euo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
skeleton="$here/gate-template.yml.in"
default_target="$root/template/.github/workflows/architect-review-gate.yml"

has_cr() { grep -q "$(printf '\r')" "$1"; }

render() {
  local line indent name script
  has_cr "$skeleton" && { echo "render-gate: CR in $skeleton" >&2; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^([[:space:]]*)@@([A-Za-z0-9._-]+)@@$ ]]; then
      indent="${BASH_REMATCH[1]}"
      name="${BASH_REMATCH[2]}"
      script="$here/$name"
      [ -f "$script" ] || { echo "render-gate: no such script: $name" >&2; return 1; }
      has_cr "$script" && { echo "render-gate: CR in $script" >&2; return 1; }
      [ "$(head -n 1 "$script")" = '#!/usr/bin/env bash' ] || { echo "render-gate: $name lacks the bash shebang" >&2; return 1; }
      [ "$(tail -c 1 "$script" | od -An -c | tr -d ' ')" = '\n' ] || { echo "render-gate: $name lacks a final newline" >&2; return 1; }
      tail -n +2 "$script" | awk -v ind="$indent" '{ if ($0 == "") print ""; else print ind $0 }'
    else
      printf '%s\n' "$line"
    fi
  done < "$skeleton"
}

case "${1:-}" in
  "")
    render
    ;;
  --check)
    file="${2:-$default_target}"
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    render > "$tmp"
    if cmp -s "$tmp" "$file"; then
      echo "render-gate: $file matches the rendered output."
    else
      echo "render-gate: $file is NOT byte-equal to the rendered output. Run tools/render-gate.sh > $file" >&2
      diff -u "$file" "$tmp" >&2 || true
      exit 1
    fi
    ;;
  *)
    echo "usage: render-gate.sh [--check [FILE]]" >&2
    exit 2
    ;;
esac
