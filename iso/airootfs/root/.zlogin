# enigmaOS live environment — auto-launch the guided installer on the main
# console. Other TTYs / SSH get a plain root shell. Exit or Ctrl-C the
# installer to drop back here and run `enigma-install` again by hand.
if [[ "$(tty)" == "/dev/tty1" ]]; then
    enigma-install
fi
