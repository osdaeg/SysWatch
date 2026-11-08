// Package logx is a tiny size-rotating log file writer.
package logx

import (
	"log"
	"os"
	"path/filepath"
	"sync"
)

type rotator struct {
	mu   sync.Mutex
	path string
	max  int64
	f    *os.File
	size int64
}

// New returns a logger writing to path, rotating to path+".1" past maxBytes.
func New(path string, maxBytes int64) *log.Logger {
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	r := &rotator{path: path, max: maxBytes}
	r.open()
	return log.New(r, "", log.LstdFlags)
}

func (r *rotator) open() {
	f, err := os.OpenFile(r.path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		r.f = nil
		return
	}
	r.f = f
	if st, err := f.Stat(); err == nil {
		r.size = st.Size()
	}
}

func (r *rotator) Write(p []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.f == nil {
		return len(p), nil
	}
	if r.size+int64(len(p)) > r.max {
		r.f.Close()
		_ = os.Remove(r.path + ".1")
		_ = os.Rename(r.path, r.path+".1")
		r.open()
		if r.f == nil {
			return len(p), nil
		}
	}
	n, err := r.f.Write(p)
	r.size += int64(n)
	return n, err
}
