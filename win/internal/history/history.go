// Package history keeps the in-memory ring buffers behind the line-widget csv
// files, so the exe never has to read a csv back over the network.
package history

import (
	"bufio"
	"io"
	"strconv"
	"strings"
	"sync"
)

// MinPoints is the smallest number of points ever kept.
const MinPoints = 11

// Point is one csv row.
type Point struct {
	T int64 // epoch seconds
	V int64
}

type series struct {
	pts    []Point
	seeded bool
}

// Store holds one series per csv file.
type Store struct {
	mu sync.Mutex
	m  map[string]*series
}

// New returns an empty store.
func New() *Store { return &Store{m: map[string]*series{}} }

func clampMax(max int) int {
	if max < MinPoints {
		return MinPoints
	}
	return max
}

func trim(pts []Point, max int) []Point {
	if len(pts) > max {
		return append([]Point(nil), pts[len(pts)-max:]...)
	}
	return pts
}

// Add appends a point and trims to max points.
func (s *Store) Add(key string, t, v int64, max int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sr := s.m[key]
	if sr == nil {
		sr = &series{}
		s.m[key] = sr
	}
	sr.pts = trim(append(sr.pts, Point{T: t, V: v}), clampMax(max))
}

// Seeded reports whether Seed already ran for key.
func (s *Store) Seeded(key string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	sr := s.m[key]
	return sr != nil && sr.seeded
}

// Seed merges points from an existing csv that are older than everything in
// memory, then marks the series as seeded.
func (s *Store) Seed(key string, r io.Reader, max int) {
	old := Parse(r)
	s.mu.Lock()
	defer s.mu.Unlock()
	sr := s.m[key]
	if sr == nil {
		sr = &series{}
		s.m[key] = sr
	}
	sr.seeded = true
	if len(old) == 0 {
		return
	}
	var keep []Point
	for _, p := range old {
		if len(sr.pts) == 0 || p.T < sr.pts[0].T {
			keep = append(keep, p)
		}
	}
	sr.pts = trim(append(keep, sr.pts...), clampMax(max))
}

// MarkSeeded flags a series as seeded without reading anything (new file).
func (s *Store) MarkSeeded(key string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sr := s.m[key]
	if sr == nil {
		sr = &series{}
		s.m[key] = sr
	}
	sr.seeded = true
}

// CSV renders the series: "timestamp,value" header, LF endings.
func (s *Store) CSV(key string) []byte {
	s.mu.Lock()
	defer s.mu.Unlock()
	var b strings.Builder
	b.WriteString("timestamp,value\n")
	if sr := s.m[key]; sr != nil {
		for _, p := range sr.pts {
			b.WriteString(strconv.FormatInt(p.T, 10))
			b.WriteByte(',')
			b.WriteString(strconv.FormatInt(p.V, 10))
			b.WriteByte('\n')
		}
	}
	return []byte(b.String())
}

// Len returns the number of points held for key.
func (s *Store) Len(key string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	if sr := s.m[key]; sr != nil {
		return len(sr.pts)
	}
	return 0
}

// Drop forgets a series.
func (s *Store) Drop(key string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.m, key)
}

// DropPrefix forgets every series whose key starts with prefix.
func (s *Store) DropPrefix(prefix string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for k := range s.m {
		if strings.HasPrefix(k, prefix) {
			delete(s.m, k)
		}
	}
}

// Parse reads a csv produced by this package (or SysWatch); bad rows are skipped.
func Parse(r io.Reader) []Point {
	var out []Point
	sc := bufio.NewScanner(r)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		i := strings.IndexByte(line, ',')
		if i <= 0 {
			continue
		}
		t, err1 := strconv.ParseInt(line[:i], 10, 64)
		v, err2 := strconv.ParseInt(strings.TrimSpace(line[i+1:]), 10, 64)
		if err1 != nil || err2 != nil {
			continue
		}
		out = append(out, Point{T: t, V: v})
	}
	return out
}
