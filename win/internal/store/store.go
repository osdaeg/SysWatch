// Package store persists the small amount of runtime data the exe needs
// between restarts: status_since per state and network transfer totals.
package store

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"

	"syswatch-win/internal/state"
)

type statusRec struct {
	Status string `json:"status"`
	Since  string `json:"since"`
}

type netRec struct {
	LastRx  uint64 `json:"last_rx"`
	LastTx  uint64 `json:"last_tx"`
	TotalRx uint64 `json:"total_rx"`
	TotalTx uint64 `json:"total_tx"`
}

type data struct {
	Status map[string]statusRec `json:"status"`
	Net    map[string]netRec    `json:"net"`
}

// Store is safe for concurrent use.
type Store struct {
	mu       sync.Mutex
	path     string
	d        data
	dirty    bool
	lastSave time.Time
}

// Open loads path (a missing or corrupt file starts empty).
func Open(path string) *Store {
	s := &Store{path: path, d: data{Status: map[string]statusRec{}, Net: map[string]netRec{}}}
	if raw, err := os.ReadFile(path); err == nil {
		var d data
		if json.Unmarshal(raw, &d) == nil {
			if d.Status != nil {
				s.d.Status = d.Status
			}
			if d.Net != nil {
				s.d.Net = d.Net
			}
		}
	}
	return s
}

// StatusSince returns when name entered status (updating the record when the
// status changed).
func (s *Store) StatusSince(name, status string, now time.Time) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.d.Status[name]
	if !ok || rec.Status != status {
		rec = statusRec{Status: status, Since: now.Local().Format(state.TimeLayout)}
		s.d.Status[name] = rec
		s.dirty = true
	}
	return rec.Since
}

// NetTotals accumulates transferred bytes across counter resets and reboots.
func (s *Store) NetTotals(name string, rx, tx uint64) (totalRx, totalTx uint64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.d.Net[name]
	if !ok {
		rec = netRec{LastRx: rx, LastTx: tx}
	} else {
		if rx >= rec.LastRx {
			rec.TotalRx += rx - rec.LastRx
		} else {
			rec.TotalRx += rx // counter reset
		}
		if tx >= rec.LastTx {
			rec.TotalTx += tx - rec.LastTx
		} else {
			rec.TotalTx += tx
		}
		rec.LastRx, rec.LastTx = rx, tx
	}
	s.d.Net[name] = rec
	s.dirty = true
	return rec.TotalRx, rec.TotalTx
}

// Flush writes the file if something changed and at least 30 s passed
// (force skips the delay).
func (s *Store) Flush(force bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.dirty || (!force && time.Since(s.lastSave) < 30*time.Second) {
		return nil
	}
	raw, err := json.MarshalIndent(s.d, "", " ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, s.path); err != nil {
		return err
	}
	s.dirty = false
	s.lastSave = time.Now()
	return nil
}
