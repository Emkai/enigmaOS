#!/bin/bash

# Memory status for waybar custom module: used RAM as text, top 15 apps
# by RAM in the tooltip. Processes with the same name (e.g. all chrome
# processes) are merged into a single row.

# Used = MemTotal - MemAvailable, same as waybar's builtin memory module
text=$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {printf "%.1f GiB", (t - a) / 1048576}' /proc/meminfo)

tooltip=$(ps -eo rss=,comm= | awk '
    {
        rss = $1
        sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
        mem[$0] += rss
    }
    END {
        for (name in mem) printf "%d\t%s\n", mem[name], name
    }
' | sort -rn | head -n 15 | awk -F '\t' '
    {
        name = $2
        # Escape for pango markup, then for JSON
        gsub(/&/, "\\&amp;", name)
        gsub(/</, "\\&lt;", name)
        gsub(/>/, "\\&gt;", name)
        gsub(/\\/, "\\\\\\\\", name)
        gsub(/"/, "\\\\\"", name)
        if ($1 >= 1048576)
            size = sprintf("%.1f GiB", $1 / 1048576)
        else
            size = sprintf("%.0f MiB", $1 / 1024)
        rows = rows (NR > 1 ? "\\n" : "") sprintf("%-16s%9s", name, size)
    }
    END { printf "%s", rows }
')

printf '{"text": "%s", "tooltip": "<tt>%s</tt>"}' "$text" "$tooltip"
