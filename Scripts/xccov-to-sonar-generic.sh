#!/bin/bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <xcresult-path> <output-xml-path>" >&2
  exit 1
fi

RESULT_BUNDLE="$1"
OUTPUT_XML="$2"
WORKSPACE_ROOT="$(pwd)"

mkdir -p "$(dirname "$OUTPUT_XML")"

escape_xml() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

{
  echo '<coverage version="1">'

  xcrun xccov view --archive --file-list "$RESULT_BUNDLE" | grep '^/' | while IFS= read -r file; do
    if [[ "$file" != "$WORKSPACE_ROOT/"* ]]; then
      continue
    fi

    if [[ ! -f "$file" ]]; then
      continue
    fi

    relative_path="${file#"$WORKSPACE_ROOT"/}"
    echo "  <file path=\"$(escape_xml "$relative_path")\">"

    xcrun xccov view --archive --file "$file" "$RESULT_BUNDLE" \
      | awk -F: '
          /^[[:space:]]*[0-9]+:/ {
            line=$1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)

            data=$2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", data)

            if (data == "*") {
              next
            }

            split(data, parts, /[[:space:]]+/)
            covered = (parts[1] + 0 > 0) ? "true" : "false"
            printf("    <lineToCover lineNumber=\"%s\" covered=\"%s\"/>\n", line, covered)
          }
        '

    echo "  </file>"
  done

  echo '</coverage>'
} > "$OUTPUT_XML"
