# Engine identity shared by bug reports, settings, saves and the mod loader.
extends RefCounted

const NAME := "Ultimate Battle Engine"
const VERSION := "0.4.1"           # bump the minor number when save or replay formats change

# File format versions. Each reader accepts every older version (see engine_save.gd);
# a newer version than these is refused with a clear message instead of misread.
const SETTINGS_FORMAT := 1
const REPLAY_FORMAT := 1
const MOD_FORMAT := 1
