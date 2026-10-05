#!/usr/bin/env bash
# Renders template/.github/workflows/architect-review-gate.yml.
#
#   tools/render-gate.sh                  write the rendered workflow to stdout
#   tools/render-gate.sh --check [FILE]   exit 1, with a diff, unless FILE (default: the
#                                         template in this repo) is byte-equal to the render
#   tools/render-gate.sh --check-masked FILE
#                                         the same, with every `>>> CONSUMER: <name>` ...
#                                         `<<< CONSUMER: <name>` region's body dropped from both
#                                         sides. For a repo's own copy, which may differ there
#                                         (this repo's decide pin). Exit 1 on an unpaired,
#                                         nested or misnamed marker, in either side.
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

# mask_consumer FILE: prints FILE with each CONSUMER region's body dropped and its two marker
# lines kept. Fails (exit 1, message on stderr) when a marker is unpaired, nested or misnamed.
mask_consumer() {
  awk -v f="$1" '
    function bad(msg) { print "render-gate: " f ":" NR ": " msg > "/dev/stderr"; failed = 1; exit 1 }
    /^[[:space:]]*# >>> CONSUMER: / {
      if (open != "") bad("nested CONSUMER region (" open ")")
      open = $0; sub(/^[[:space:]]*# >>> CONSUMER: /, "", open); print; next
    }
    /^[[:space:]]*# <<< CONSUMER: / {
      name = $0; sub(/^[[:space:]]*# <<< CONSUMER: /, "", name)
      if (open == "") bad("closing marker with no opening: " name)
      if (name != open) bad("closing marker " name " does not match opening " open)
      open = ""; print; next
    }
    open == "" { print }
    END { if (!failed && open != "") { print "render-gate: " f ": unclosed CONSUMER region: " open > "/dev/stderr"; exit 1 } }
  ' "$1"
}

has_cr() { ! cmp -s <(tr -d '\r' < "$1") "$1"; }

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
  --check-masked)
    file="${2:-}"
    [ -n "$file" ] || { echo "usage: render-gate.sh --check-masked FILE" >&2; exit 2; }
    [ -f "$file" ] || { echo "render-gate: no such file: $file" >&2; exit 1; }
    has_cr "$file" && { echo "render-gate: CR in $file" >&2; exit 1; }
    # awk and grep split lines on LF only, but a YAML parser also splits on NEL and U+2028, so a
    # region body could hide a line from every check here. Both files are plain ASCII.
    LC_ALL=C grep -aq '[^ -~]' "$file" && { echo "render-gate: $file holds a byte outside printable ASCII" >&2; exit 1; }
    [ -z "$(tail -c 1 "$file")" ] || { echo "render-gate: $file lacks a final newline" >&2; exit 1; }
    tmp="$(mktemp)"; mtmp="$(mktemp)"; ftmp="$(mktemp)"
    trap 'rm -f "$tmp" "$mtmp" "$ftmp"' EXIT
    render > "$tmp"
    mask_consumer "$tmp" > "$mtmp"
    mask_consumer "$file" > "$ftmp"
    if cmp -s "$mtmp" "$ftmp"; then
      echo "render-gate: $file matches the rendered output outside its CONSUMER regions (the regions themselves are not checked here)."
    else
      echo "render-gate: $file differs from the rendered output outside its CONSUMER regions. Regenerate it with tools/render-gate.sh and re-apply only the CONSUMER regions." >&2
      diff -u "$ftmp" "$mtmp" >&2 || true
      exit 1
    fi
    ;;
  *)
    echo "usage: render-gate.sh [--check [FILE] | --check-masked FILE]" >&2
    exit 2
    ;;
esac
