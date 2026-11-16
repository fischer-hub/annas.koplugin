#!/bin/sh
# Background download job for the Anna's Archive plugin.
#
# Runs outside the KOReader process, so the UI thread never waits on the
# network. For each LibGen mirror it fetches the ads.php page, extracts the
# get.php link, and downloads the file, using aria2c (multi-connection) when
# a binary is given, or curl otherwise. Transient failures (for example HTTP
# 503 from an overloaded mirror) are retried with a growing delay.
#
# usage: download_job.sh STATUS_FILE PID_FILE OUT_FILE MD5 FORMAT ARIA2C_BIN MIRROR...
#
# STATUS_FILE receives exactly one line when the job finishes:
#   OK <absolute path of the saved book>
#   FAIL <reason>
# PID_FILE receives the PID of this shell so the plugin can stop a stuck job.
#
# Optional environment: ANNAS_CA_BUNDLE, path to a CA bundle for aria2c.

# Byte-oriented tools (tr, head) must not choke on binary book data.
LC_ALL=C
export LC_ALL

if [ "$#" -lt 7 ]; then
    echo "usage: $0 STATUS_FILE PID_FILE OUT_FILE MD5 FORMAT ARIA2C_BIN MIRROR..." >&2
    exit 2
fi

status_file=$1
pid_file=$2
out_file=$3
md5=$4
format=$5
aria2c_bin=$6
shift 6

echo $$ > "$pid_file"

user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.4 Safari/605.1.15"
accept="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
accept_language="en-US,en;q=0.9"
out_dir=$(dirname "$out_file")
part_name=$(basename "$out_file").part
part_file="$out_dir/$part_name"

# Attempts per mirror for the page and file fetches, and the base delay
# between attempts. The delay grows with each attempt (5s, 10s, ...).
ATTEMPTS=3
RETRY_BASE_DELAY=5

finish() {
    printf '%s\n' "$1" > "$status_file.tmp"
    mv "$status_file.tmp" "$status_file"
    rm -f "$pid_file"
    exit "$2"
}

# Fetch the ads.php page for $md5 on $1 and print the get.php link.
# Returns non-zero if the page can't be fetched or has no link.
find_link() {
    page=$(curl -L -s -f --compressed --max-time 8 \
        -A "$user_agent" -H "Accept: $accept" -H "Accept-Language: $accept_language" \
        "https://$1/ads.php?md5=$md5" 2>/dev/null) || return 1
    link=$(printf '%s' "$page" | grep -o 'href="[^"]*get\.php[^"]*"' | head -n 1 | sed 's/^href="//; s/"$//')
    [ -n "$link" ] || return 1
    printf '%s\n' "$link"
}

# Download $1 into $part_file. Tries aria2c first and falls back to curl on
# the same URL if aria2c is missing or fails (for example on a TLS error).
# Returns non-zero on any transfer failure.
fetch_file() {
    rm -f "$part_file"
    if [ -n "$aria2c_bin" ] && [ -x "$aria2c_bin" ]; then
        # aria2c ships without a CA bundle on some devices, so the plugin can
        # pass one in ANNAS_CA_BUNDLE.
        if [ -n "$ANNAS_CA_BUNDLE" ] && [ -f "$ANNAS_CA_BUNDLE" ]; then
            "$aria2c_bin" -x16 -s16 -k1M --max-tries=2 --retry-wait=3 \
                --connect-timeout=20 --timeout=30 \
                --ca-certificate="$ANNAS_CA_BUNDLE" \
                --allow-overwrite=true --auto-file-renaming=false --file-allocation=none \
                --console-log-level=warn --summary-interval=0 \
                --user-agent="$user_agent" \
                -d "$out_dir" -o "$part_name" "$1" >/dev/null 2>&1
        else
            "$aria2c_bin" -x16 -s16 -k1M --max-tries=2 --retry-wait=3 \
                --connect-timeout=20 --timeout=30 \
                --allow-overwrite=true --auto-file-renaming=false --file-allocation=none \
                --console-log-level=warn --summary-interval=0 \
                --user-agent="$user_agent" \
                -d "$out_dir" -o "$part_name" "$1" >/dev/null 2>&1
        fi
        if [ -s "$part_file" ] && [ ! -e "$part_file.aria2" ]; then
            return 0
        fi
        rm -f "$part_file" "$part_file.aria2"
    fi
    curl -L -f -s --compressed --connect-timeout 20 --max-time 1800 \
        -A "$user_agent" -o "$part_file" "$1" >/dev/null 2>&1 || return 1
    [ -s "$part_file" ] || return 1
}

# libgen sometimes answers with an HTML error page and a 200 status instead
# of the file. Returns 0 when the downloaded file looks like such a page.
is_html_page() {
    format_upper=$(printf '%s' "$format" | tr '[:lower:]' '[:upper:]')
    if [ "$format_upper" = "HTM" ] || [ "$format_upper" = "HTML" ]; then
        return 1
    fi
    head -c 512 "$part_file" | tr '[:upper:]' '[:lower:]' | grep -q -E '^[[:space:]]*(<!doctype html|<html)'
}

last_error="could not fetch download link from source page."

for mirror in "$@"; do
    attempt=1
    while [ "$attempt" -le "$ATTEMPTS" ]; do
        if link=$(find_link "$mirror"); then
            url="https://$mirror/$link"
            if fetch_file "$url"; then
                if is_html_page; then
                    rm -f "$part_file"
                    last_error="$mirror returned an HTML page instead of the file"
                    break
                fi
                if ! mv "$part_file" "$out_file"; then
                    rm -f "$part_file"
                    finish "FAIL could not move the download into place: $out_file" 1
                fi
                finish "OK $out_file" 0
            fi
            rm -f "$part_file"
            last_error="Network/HTTP error or empty download from $mirror"
        else
            last_error="Network/HTTP error fetching the download page on $mirror"
        fi
        if [ "$attempt" -lt "$ATTEMPTS" ]; then
            sleep $((RETRY_BASE_DELAY * attempt))
        fi
        attempt=$((attempt + 1))
    done
done

finish "FAIL $last_error" 1
