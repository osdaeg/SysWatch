//go:build !windows

package i18n

import "os"

// DetectLang reads the usual POSIX environment variables.
func DetectLang() string {
	for _, k := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
		if v := os.Getenv(k); v != "" && v != "C" && v != "POSIX" {
			return NormalizeLang(v)
		}
	}
	return "en"
}
