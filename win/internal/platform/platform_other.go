//go:build !windows

package platform

import "os/exec"

// SingleInstance is a no-op off Windows.
func SingleInstance(name string) (release func(), ok bool) { return func() {}, true }

// Open uses xdg-open (development convenience only).
func Open(path string) error { return exec.Command("xdg-open", path).Start() }

// Autostart is not supported off Windows.
func Autostart() bool { return false }

// SetAutostart is a no-op off Windows.
func SetAutostart(enable bool, exe string) error { return nil }
