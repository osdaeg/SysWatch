//go:build windows

package i18n

import "golang.org/x/sys/windows"

// DetectLang returns the primary subtag of the Windows UI language.
func DetectLang() string {
	langs, err := windows.GetUserPreferredUILanguages(windows.MUI_LANGUAGE_NAME)
	if err != nil || len(langs) == 0 {
		return "en"
	}
	return NormalizeLang(langs[0])
}
