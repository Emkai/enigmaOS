#!/bin/bash

# Swap left and right monitor positions in Hyprland.
# Recomputes positions using logical (scaled) widths so HiDPI + non-HiDPI
# monitors butt up against each other without gaps or overlap.

monitors=$(hyprctl monitors -j)
count=$(echo "$monitors" | jq 'length')

if [ "$count" -ne 2 ]; then
    echo "Expected 2 monitors, found $count. Aborting."
    exit 1
fi

# Sort by current x so [0] is left, [1] is right; then swap.
read -r left_name left_w left_h left_rate left_scale < <(
    echo "$monitors" | jq -r 'sort_by(.x) | .[0] | "\(.name) \(.width) \(.height) \(.refreshRate) \(.scale)"'
)
read -r right_name right_w right_h right_rate right_scale < <(
    echo "$monitors" | jq -r 'sort_by(.x) | .[1] | "\(.name) \(.width) \(.height) \(.refreshRate) \(.scale)"'
)

left_rate=$(printf "%.0f" "$left_rate")
right_rate=$(printf "%.0f" "$right_rate")

# After swap: right monitor goes to x=0, left monitor goes to x=(right's logical width).
new_left_x=$(awk -v w="$right_w" -v s="$right_scale" 'BEGIN { printf "%d", w / s }')

echo "Swapping: $left_name <-> $right_name"

# Park the left monitor far off-screen first to avoid a transient overlap
# warning while the right monitor is being repositioned to x=0.
hyprctl keyword monitor "$left_name,${left_w}x${left_h}@${left_rate},20000x0,${left_scale}"
hyprctl keyword monitor "$right_name,${right_w}x${right_h}@${right_rate},0x0,${right_scale}"
hyprctl keyword monitor "$left_name,${left_w}x${left_h}@${left_rate},${new_left_x}x0,${left_scale}"

echo "Done."
