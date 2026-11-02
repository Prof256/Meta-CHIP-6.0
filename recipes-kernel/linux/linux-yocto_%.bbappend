FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

COMPATIBLE_MACHINE:chip = "chip"

SRC_URI:append:chip = " file://chip.cfg"

