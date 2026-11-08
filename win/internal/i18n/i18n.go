// Package i18n replicates SysWatch's sw_translate: .conf files made of line
// pairs, "en=<source text>" followed by "<lang>=<translation>".
package i18n

import (
	"bufio"
	"embed"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

//go:embed lang/*.conf
var embedded embed.FS

// Translator holds translations for any number of languages.
type Translator struct {
	mu   sync.RWMutex
	lang string
	data map[string]map[string]string // lang -> english text -> translation
}

// New returns a translator with the embedded tables loaded.
func New() *Translator {
	t := &Translator{data: map[string]map[string]string{}}
	entries, _ := embedded.ReadDir("lang")
	for _, e := range entries {
		f, err := embedded.Open("lang/" + e.Name())
		if err != nil {
			continue
		}
		t.Load(f)
		f.Close()
	}
	return t
}

// NormalizeLang reduces "es-AR", "ES_ar" to "es"; empty stays empty.
func NormalizeLang(l string) string {
	l = strings.ToLower(strings.TrimSpace(l))
	if i := strings.IndexAny(l, "-_."); i >= 0 {
		l = l[:i]
	}
	return l
}

// SetLang selects the target language ("" or "en" disables translation).
func (t *Translator) SetLang(l string) {
	t.mu.Lock()
	t.lang = NormalizeLang(l)
	t.mu.Unlock()
}

// Lang returns the active language.
func (t *Translator) Lang() string {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.lang
}

// Load parses a .conf stream. Later loads override earlier entries.
// Language codes are case-insensitive; '#' starts a comment line.
func (t *Translator) Load(r io.Reader) {
	t.mu.Lock()
	defer t.mu.Unlock()
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	src := ""
	haveSrc := false
	first := true
	for sc.Scan() {
		line := sc.Text()
		if first {
			line = strings.TrimPrefix(line, "\ufeff")
			first = false
		}
		line = strings.TrimRight(line, "\r")
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		i := strings.IndexByte(line, '=')
		if i <= 0 {
			continue
		}
		code := strings.ToLower(strings.TrimSpace(line[:i]))
		val := line[i+1:]
		if code == "en" {
			src, haveSrc = val, true
			continue
		}
		if !haveSrc {
			continue
		}
		m := t.data[code]
		if m == nil {
			m = map[string]string{}
			t.data[code] = m
		}
		m[src] = val
	}
}

// LoadDir loads every *.conf file in dir (missing dir is not an error).
func (t *Translator) LoadDir(dir string) {
	files, _ := filepath.Glob(filepath.Join(dir, "*.conf"))
	for _, p := range files {
		if f, err := os.Open(p); err == nil {
			t.Load(f)
			f.Close()
		}
	}
}

// T translates an English text; unknown texts and "en" return the input.
func (t *Translator) T(s string) string {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if t.lang == "" || t.lang == "en" {
		return s
	}
	if v, ok := t.data[t.lang][s]; ok && v != "" {
		return v
	}
	return s
}
