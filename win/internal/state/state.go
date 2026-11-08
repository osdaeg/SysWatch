// Package state builds SysWatch .state content: sorted key=value lines, LF
// endings, UTF-8 without BOM, values sanitized like sw_sanitize_state_value.
package state

import (
	"sort"
	"strconv"
	"strings"
	"time"
)

// TimeLayout is the timestamp format used inside .state files (local time).
const TimeLayout = "2006-01-02 15:04:05"

// Status values understood by SysWatch.
const (
	OK       = "OK"
	Warning  = "WARNING"
	Critical = "CRITICAL"
	Unknown  = "UNKNOWN"
	None     = "NONE"
)

// Sanitize mirrors sw_sanitize_state_value: CR, LF and TAB become spaces and
// runs of spaces are squeezed into one.
func Sanitize(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	prevSpace := false
	for _, r := range s {
		if r == '\r' || r == '\n' || r == '\t' {
			r = ' '
		}
		if r == ' ' {
			if prevSpace {
				continue
			}
			prevSpace = true
		} else {
			prevSpace = false
		}
		b.WriteRune(r)
	}
	return b.String()
}

// State is an unordered key/value set; serialization sorts keys bytewise,
// which is how SysWatch's own states are laid out.
type State struct {
	m map[string]string
}

// New returns an empty state.
func New() *State { return &State{m: map[string]string{}} }

// Set stores a sanitized value.
func (s *State) Set(key, value string) { s.m[key] = Sanitize(value) }

// Get returns a value.
func (s *State) Get(key string) (string, bool) {
	v, ok := s.m[key]
	return v, ok
}

// Delete removes a key.
func (s *State) Delete(key string) { delete(s.m, key) }

// Len is the number of keys.
func (s *State) Len() int { return len(s.m) }

// Bytes serializes the state: "key=value\n" lines sorted by key.
func (s *State) Bytes() []byte {
	keys := make([]string, 0, len(s.m))
	for k := range s.m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(s.m[k])
		b.WriteByte('\n')
	}
	return []byte(b.String())
}

// Num returns a pointer to f, for optional Field numbers.
func Num(f float64) *float64 { return &f }

// Field describes one value plus its presentation keys.
type Field struct {
	Key      string
	Value    string
	Label    string
	Order    int
	Unit     string
	Render   string
	Widget   string
	Scale    string
	Min      *float64
	Max      *float64
	Warning  *float64
	Critical *float64
	Hidden   bool
}

func fmtNum(f float64) string { return strconv.FormatFloat(f, 'f', -1, 64) }

// AddField writes the value and every presentation key that is set.
func (s *State) AddField(f Field) {
	s.Set(f.Key, f.Value)
	if f.Label != "" {
		s.Set(f.Key+".label", f.Label)
	}
	if f.Order > 0 {
		s.Set(f.Key+".order", strconv.Itoa(f.Order))
	}
	if f.Unit != "" {
		s.Set(f.Key+".unit", f.Unit)
	}
	if f.Render != "" {
		s.Set(f.Key+".render", f.Render)
	}
	if f.Widget != "" {
		s.Set(f.Key+".widget", f.Widget)
	}
	if f.Scale != "" {
		s.Set(f.Key+".scale", f.Scale)
	}
	if f.Min != nil {
		s.Set(f.Key+".min", fmtNum(*f.Min))
	}
	if f.Max != nil {
		s.Set(f.Key+".max", fmtNum(*f.Max))
	}
	if f.Warning != nil {
		s.Set(f.Key+".warning", fmtNum(*f.Warning))
	}
	if f.Critical != nil {
		s.Set(f.Key+".critical", fmtNum(*f.Critical))
	}
	if f.Hidden {
		s.Set(f.Key+".hidden", "true")
	}
}

// SetModule writes the module.* identity keys.
func (s *State) SetModule(icon, label string, order int, version string) {
	s.Set("module.icon", icon)
	s.Set("module.label", label)
	s.Set("module.order", strconv.Itoa(order))
	s.Set("module_version", version)
}

// SetHost writes the sw_hostname block. Remote states are never hidden.
func (s *State) SetHost(host, hostLabel string, hidden bool) {
	s.Set("sw_hostname", host)
	s.Set("sw_hostname.color", "yellow")
	if hidden {
		s.Set("sw_hostname.hidden", "true")
	} else {
		s.Set("sw_hostname.hidden", "false")
	}
	s.Set("sw_hostname.label", hostLabel)
	s.Set("sw_hostname.order", "1000")
}

// SetTimestamp writes timestamp in local time.
func (s *State) SetTimestamp(t time.Time) { s.Set("timestamp", t.Local().Format(TimeLayout)) }

// Level maps a value to OK/WARNING/CRITICAL using >= thresholds.
func Level(v, warning, critical float64) string {
	switch {
	case v >= critical:
		return Critical
	case v >= warning:
		return Warning
	default:
		return OK
	}
}

// Worst returns the more severe of two statuses.
func Worst(a, b string) string {
	rank := map[string]int{OK: 1, Warning: 3, Critical: 4, Unknown: 2, None: 0}
	if rank[b] > rank[a] {
		return b
	}
	return a
}
