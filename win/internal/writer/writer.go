// Package writer is the only way out of the program: it checks the .import
// control file, keeps csv history in memory and writes .state/.timer/.csv
// atomically with LF endings.
package writer

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"syswatch-win/internal/history"
	"syswatch-win/internal/state"
)

// ErrNotReady means the .import control file is missing or unreachable.
var ErrNotReady = errors.New("output folder not ready (.import missing)")

// ImportMarker is the control file SysWatch creates in its import/ folder.
const ImportMarker = ".import"

// Output is everything one module cycle wants to publish for one state.
type Output struct {
	Name       string           // state name without host, e.g. "cpu", "disk_c"
	State      *state.State     // state content
	Series     map[string]int64 // key -> value; one <state>.<key>.csv per entry
	IntervalS  int              // used for the timer when TimerTotal is 0
	TimerTotal int              // explicit TOTAL (minutes); 0 = IntervalS/60+5
	CSVPoints  int              // csv rows to keep
}

// Writer publishes outputs into a folder.
type Writer struct {
	mu      sync.RWMutex
	dir     string
	host    string
	timeout time.Duration
	hist    *history.Store
	now     func() time.Time

	checkMu   sync.Mutex
	checkedAt time.Time
	lastOK    bool
}

// New creates a Writer.
func New(hist *history.Store) *Writer {
	return &Writer{hist: hist, timeout: 3 * time.Second, now: time.Now}
}

// Configure sets destination folder, host name used in file names, and the
// timeout of the .import check.
func (w *Writer) Configure(dir, host string, timeout time.Duration) {
	w.mu.Lock()
	w.dir, w.host = dir, SafeHost(host)
	if timeout > 0 {
		w.timeout = timeout
	}
	w.mu.Unlock()
	w.checkMu.Lock()
	w.checkedAt = time.Time{}
	w.checkMu.Unlock()
}

// Dir returns the configured folder.
func (w *Writer) Dir() string {
	w.mu.RLock()
	defer w.mu.RUnlock()
	return w.dir
}

// Host returns the sanitized host used in file names.
func (w *Writer) Host() string {
	w.mu.RLock()
	defer w.mu.RUnlock()
	return w.host
}

// Stem is the common file name prefix of a state: "<name>-<host>".
func (w *Writer) Stem(name string) string { return name + "-" + w.Host() }

// Ready reports whether <dir>\.import exists. The check runs with a timeout so
// a dead network share cannot freeze the caller, and its result is cached for
// two seconds so concurrent modules do not each pay for it.
func (w *Writer) Ready() bool {
	w.mu.RLock()
	dir, timeout := w.dir, w.timeout
	w.mu.RUnlock()
	if dir == "" {
		return false
	}
	w.checkMu.Lock()
	defer w.checkMu.Unlock()
	if !w.checkedAt.IsZero() && time.Since(w.checkedAt) < 2*time.Second {
		return w.lastOK
	}
	done := make(chan bool, 1)
	go func() {
		_, err := os.Stat(filepath.Join(dir, ImportMarker))
		done <- err == nil
	}()
	select {
	case ok := <-done:
		w.lastOK = ok
	case <-time.After(timeout):
		w.lastOK = false
	}
	w.checkedAt = time.Now()
	return w.lastOK
}

func (w *Writer) csvKey(name, key string) string { return w.Stem(name) + "." + key }

// Submit records the series in memory (always) and, when the folder is ready,
// writes the csv files, the state and the timer, in that order.
func (w *Writer) Submit(o Output) error {
	now := w.now()
	for key, v := range o.Series {
		w.hist.Add(w.csvKey(o.Name, key), now.Unix(), v, o.CSVPoints)
	}
	if !w.Ready() {
		return ErrNotReady
	}
	dir, stem := w.Dir(), w.Stem(o.Name)

	keys := make([]string, 0, len(o.Series))
	for key := range o.Series {
		keys = append(keys, key)
	}
	for _, key := range keys {
		hk := w.csvKey(o.Name, key)
		path := filepath.Join(dir, stem+"."+key+".csv")
		if !w.hist.Seeded(hk) {
			if f, err := os.Open(path); err == nil {
				w.hist.Seed(hk, f, o.CSVPoints)
				f.Close()
			} else if errors.Is(err, fs.ErrNotExist) {
				w.hist.MarkSeeded(hk)
			}
		}
		if err := writeAtomic(dir, stem+"."+key+".csv", w.hist.CSV(hk)); err != nil {
			return err
		}
	}
	if o.State != nil {
		if err := writeAtomic(dir, stem+".state", o.State.Bytes()); err != nil {
			return err
		}
	}
	total := o.TimerTotal
	if total <= 0 {
		total = o.IntervalS/60 + 5
	}
	timer := fmt.Sprintf("%s=TOTAL:%d|ACTION:deletestate|COUNT:%d\n", stem, total, total)
	return writeAtomic(dir, stem+".timer", []byte(timer))
}

// Remove deletes the state, timer and csv files of name, and forgets its
// in-memory history.
func (w *Writer) Remove(name string) error {
	w.hist.DropPrefix(w.Stem(name) + ".")
	if !w.Ready() {
		return ErrNotReady
	}
	dir, stem := w.Dir(), w.Stem(name)
	var firstErr error
	rm := func(p string) {
		if err := os.Remove(p); err != nil && !errors.Is(err, fs.ErrNotExist) && firstErr == nil {
			firstErr = err
		}
	}
	rm(filepath.Join(dir, stem+".state"))
	rm(filepath.Join(dir, stem+".timer"))
	if matches, err := filepath.Glob(filepath.Join(dir, stem+".*.csv")); err == nil {
		for _, m := range matches {
			rm(m)
		}
	}
	return firstErr
}

// writeAtomic writes to a hidden temporary file in the same folder and renames
// it over the destination, retrying briefly because a reader on the other side
// of an SMB share may hold the target open.
func writeAtomic(dir, name string, data []byte) error {
	tmp := filepath.Join(dir, "."+name+".tmp")
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	var err error
	for i := 0; i < 5; i++ {
		if err = os.Rename(tmp, filepath.Join(dir, name)); err == nil {
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	os.Remove(tmp)
	return err
}

// SafeHost returns the short host name usable in a file name: text before the
// first dot, only letters, digits, '-' and '_'.
func SafeHost(h string) string {
	if i := strings.IndexByte(h, '.'); i > 0 {
		h = h[:i]
	}
	var b strings.Builder
	for _, r := range h {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
			b.WriteRune(r)
		case r == ' ' || r == '.':
			b.WriteByte('-')
		}
	}
	if b.Len() == 0 {
		return "host"
	}
	return b.String()
}

// Slug turns a free-form name into a state name: lowercase letters, digits and
// '_' only ("Wi-Fi" -> "wi_fi", "vEthernet (WSL)" -> "vethernet_wsl").
func Slug(s string) string {
	var b strings.Builder
	lastUnderscore := true
	for _, r := range strings.ToLower(s) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
			lastUnderscore = false
		} else if !lastUnderscore {
			b.WriteByte('_')
			lastUnderscore = true
		}
	}
	return strings.Trim(b.String(), "_")
}
