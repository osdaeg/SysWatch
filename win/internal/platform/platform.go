// Package platform isolates the few operating-system specifics: single
// instance, opening files/folders, and start-with-Windows.
package platform

import "os"

// Exe returns the path of the running executable.
func Exe() string {
	p, err := os.Executable()
	if err != nil {
		return ""
	}
	return p
}
