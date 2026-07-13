#!/usr/bin/env bash

# Lists all tasks as: INDEX\tClient / Assignment / Task
cmpy_task_list() {
    cmpy task list 2>/dev/null | awk -F'\t' '{print $1 "\t" $2 " / " $3 " / " $4}'
}

# Returns total hours logged today
cmpy_today_hours() {
    local today
    today=$(date +%Y-%m-%d)
    local total
    total=$(cmpy time list 2>/dev/null | awk -F'\t' -v d="$today" '$4 == d {sum += $5} END {printf "%.2f", sum}')
    echo "${total:-0.00}"
}

# Returns total hours logged for a given month (default: current month)
cmpy_month_hours() {
    local month="${1:-$(date +%Y-%m)}"
    local total
    total=$(cmpy time list 2>/dev/null | awk -F'\t' -v m="$month" 'substr($4,1,7) == m {sum += $5} END {printf "%.2f", sum}')
    echo "${total:-0.00}"
}

# Returns recent time entries, most recent first
# Format: DATE  HOURSh  Client / Assignment / Task
cmpy_recent_entries() {
    local limit="${1:-10}"
    cmpy time list 2>/dev/null | tail -n "$limit" | tac | awk -F'\t' '{printf "%s  %sh  %s / %s / %s\n", $4, $5, $1, $2, $3}'
}

# Adds a time entry. Sends notification on success/failure.
cmpy_add_time() {
    local task_ref="$1"
    local hours="$2"
    local date="${3:-$(date +%Y-%m-%d)}"

    if cmpy time add -t "$task_ref" -h "$hours" -d "$date" 2>/dev/null; then
        notify-send "Time" "Added ${hours}h on ${date}"
    else
        notify-send "Time" "Failed to add time entry"
    fi
}

# Lists clients as: INDEX\tNAME
cmpy_client_list() {
    cmpy client list 2>/dev/null | awk -F'\t' '{print $1 "\t" $2}'
}

# Generates a monthly report PDF
cmpy_generate_report() {
    local month="$1"
    local out="${2:-report-${month}.pdf}"

    res=$(cmpy report -m $month -o $out)
    if [$? -eq 0 ]; then
        notify-send "Time" "Report written to $out"
    else
        notify-send "Time" "Failed to generate report $res"
    fi
}

# Generates an invoice PDF for a specific client
cmpy_generate_invoice() {
    local month="$1"
    local client_ref="$2"
    local out="${3:-invoice-${month}.pdf}"

    if cmpy invoice -m "$month" -c "$client_ref" -f pdf -o "$out" 2>/dev/null; then
        notify-send "Time" "Invoice written to $out"
    else
        notify-send "Time" "Failed to generate invoice"
    fi
}
