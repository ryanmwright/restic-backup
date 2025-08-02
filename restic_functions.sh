#!/bin/sh

restic-mount() {
    MNT_PATH="${1-/mnt/restic}"
    restic mount $MNT_PATH
}

restic-snapshots() {
    local mode=""
    local raw_input=""
    local date_input=""
    local host_filter=""
    local path_filter=""
    local tags=()

    if [[ $# -eq 0 ]]; then
        cat <<EOF
Usage: restic-snapshots [--before VALUE | --after VALUE]
                       [--tag TAG]... [--host HOSTNAME] [--path GLOB_PATTERN]

VALUE can be either:
  - A number of days (e.g., 7)
  - A date string (e.g., 2024-12-01)

GLOB_PATTERN supports '*', '?' wildcards (case-insensitive).

Examples:
  restic-snapshots --after 7 --tag daily --tag weekly
  restic-snapshots --before 2024-06-01 --tag weekly --host myhost
  restic-snapshots --after 14 --path "/var/*/log"
EOF
        return 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --before)
                mode="<"
                raw_input="$2"
                shift 2
                ;;
            --after)
                mode=">"
                raw_input="$2"
                shift 2
                ;;
            --tag)
                tags+=("$2")
                shift 2
                ;;
            --host)
                host_filter="$2"
                shift 2
                ;;
            --path)
                path_filter="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown argument: $1" >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$mode" || -z "$raw_input" ]]; then
        #echo "Error: You must specify --before/--after with a value" >&2
        #return 1
        mode=">"
        raw_input="1900-01-01"
    fi

    # Detect date or days input
    if [[ "$raw_input" =~ ^[0-9]+$ ]]; then
        date_input=$(date -d "-$raw_input days" --iso-8601=seconds)
    else
        if ! date_input=$(date -d "$raw_input" --iso-8601=seconds 2>/dev/null); then
            echo "Error: Invalid date format: $raw_input" >&2
            return 1
        fi
    fi

    # Convert glob to case-insensitive regex for path filter
    if [[ -n "$path_filter" ]]; then
        path_regex=$(printf '%s\n' "$path_filter" | sed \
            -e 's/[.^$+(){}|[\]\\]/\\&/g' \
            -e 's/\*/.*/g' \
            -e 's/\?/.?/g')
        path_regex="(?i)^${path_regex}$"
    fi

    # Build jq tag filter for multiple tags (any tag matches)
    local jq_tag_filter=""
    if (( ${#tags[@]} > 0 )); then
        # Build jq-style array string: ["tag1","tag2"]
        local jq_tags_array
        jq_tags_array=$(printf '"%s",' "${tags[@]}")
        jq_tags_array="[${jq_tags_array%,}]"
        jq_tag_filter=" and ((.tags // []) | any(. as \$t | $jq_tags_array | index(\$t)))"
    fi

    # Construct jq filter
    local jq_expr=".[] | select(.time $mode \$DATE"
    jq_expr+="$jq_tag_filter"
    [[ -n "$host_filter" ]] && jq_expr+=" and (.hostname == \"$host_filter\")"
    if [[ -n "$path_filter" ]]; then
        jq_expr+=" and ((.paths // []) | map(test(\$PATH_REGEX)) | any)"
    fi
    jq_expr+=") | .short_id + \" \" + .time"

    echo "Filtering snapshots where time $mode $date_input"
    (( ${#tags[@]} )) && echo "  Tags: ${tags[*]}"
    [[ -n "$host_filter" ]] && echo "  Host: $host_filter"
    [[ -n "$path_filter" ]] && echo "  Path matches glob (case-insensitive): $path_filter"

    restic snapshots --json | jq -r \
        --arg DATE "$date_input" \
        --arg PATH_REGEX "$path_regex" \
        "$jq_expr"
}