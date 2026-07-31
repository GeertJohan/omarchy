if omarchy-hw-framework16; then
  # qmk-hid may be absent from the ISO/binary repo (the 3.8.4 ISO shipped
  # before it was added to omarchy-other.packages). Fall back to the AUR
  # when online, and don't fail the whole install over an optional
  # keyboard tool when offline.
  omarchy-pkg-add qmk-hid || omarchy-pkg-aur-add qmk-hid ||
    echo "Warning: qmk-hid not installed (Framework 16 RGB keyboard tool); install later with: yay -S qmk-hid" >&2
fi
