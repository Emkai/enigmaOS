DISPLAY=('Option A' 'Option B' 'Option C')
CMD=('echo "Option A"' 'echo "Option B"' 'echo "Option C"')

# Get the index of the selected option
index=$(printf '%s\n' "${DISPLAY[@]}" | wofi --show dmenu --prompt "Power Menu")

selected="${index#*:text:}" # looks like this: 0:text:Option A

# Display the selected option
echo "Selected: $selected"


# Run the command corresponding to the selected option
eval "$CMD[$index]"
