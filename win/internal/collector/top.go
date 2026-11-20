package collector

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/shirou/gopsutil/v3/process"

	"syswatch-win/internal/state"
	"syswatch-win/internal/writer"
)

// TopN is how many processes a card lists.
const TopN = 8

// procRow is one process observation (Value is a percentage).
type procRow struct {
	Name  string
	PID   int32
	Value float64
}

// rankedProc is a process name after grouping its instances.
type rankedProc struct {
	Name  string
	PID   int32 // instance with the highest value
	N     int   // number of instances
	Value float64
}

// rankByName sums rows that share a name, drops zero values and returns the
// top n by value, descending (ties broken by name so output is stable).
func rankByName(rows []procRow, n int) []rankedProc {
	type agg struct {
		sum, best float64
		pid       int32
		n         int
	}
	m := map[string]*agg{}
	for _, r := range rows {
		if r.Name == "" || r.Value <= 0 {
			continue
		}
		a := m[r.Name]
		if a == nil {
			a = &agg{}
			m[r.Name] = a
		}
		a.sum += r.Value
		a.n++
		if r.Value > a.best {
			a.best, a.pid = r.Value, r.PID
		}
	}
	out := make([]rankedProc, 0, len(m))
	for name, a := range m {
		out = append(out, rankedProc{Name: name, PID: a.pid, N: a.n, Value: a.sum})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Value != out[j].Value {
			return out[i].Value > out[j].Value
		}
		return out[i].Name < out[j].Name
	})
	if len(out) > n {
		out = out[:n]
	}
	return out
}

// procLabel is "name (PID)" like the Linux cards, or "name (×N)" when several
// instances were added together.
func procLabel(r rankedProc) string {
	if r.N > 1 {
		return fmt.Sprintf("%s (×%d)", r.Name, r.N)
	}
	return fmt.Sprintf("%s (%d)", r.Name, r.PID)
}

// processKey makes a process name usable as a state key (spaces and '=' break
// the key=value format).
func processKey(name string) string {
	r := strings.NewReplacer(" ", "_", "=", "_", "\t", "_", "\r", "_", "\n", "_")
	return r.Replace(name)
}

// topCPUSampler measures per-process CPU between consecutive calls.
type topCPUSampler struct {
	mu       sync.Mutex
	prev     map[int32]float64
	prevTime time.Time
	cores    int
}

func newTopCPUSampler(cores int) *topCPUSampler {
	if cores < 1 {
		cores = 1
	}
	return &topCPUSampler{prev: map[int32]float64{}, cores: cores}
}

// Sample returns CPU % per process since the previous call, normalized by the
// number of logical cores so it compares with the overall usage. Processes
// that deny access (protected system processes) are skipped.
func (s *topCPUSampler) Sample(ctx context.Context, now time.Time) []procRow {
	s.mu.Lock()
	defer s.mu.Unlock()
	procs, err := process.ProcessesWithContext(ctx)
	if err != nil {
		return nil
	}
	cur := make(map[int32]float64, len(procs))
	var rows []procRow
	dt := now.Sub(s.prevTime).Seconds()
	for _, p := range procs {
		t, err := p.TimesWithContext(ctx)
		if err != nil {
			continue
		}
		total := t.User + t.System
		cur[p.Pid] = total
		prev, ok := s.prev[p.Pid]
		if !ok || dt <= 0 || total < prev {
			continue
		}
		name, err := p.NameWithContext(ctx)
		if err != nil {
			continue
		}
		pct := (total - prev) / dt * 100 / float64(s.cores)
		rows = append(rows, procRow{Name: trimExe(name), PID: p.Pid, Value: pct})
	}
	s.prev, s.prevTime = cur, now
	return rows
}

// memoryRows lists resident memory (working set on Windows) as a percentage of
// total RAM, per process.
func memoryRows(ctx context.Context, totalBytes uint64) []procRow {
	if totalBytes == 0 {
		return nil
	}
	procs, err := process.ProcessesWithContext(ctx)
	if err != nil {
		return nil
	}
	var rows []procRow
	for _, p := range procs {
		mi, err := p.MemoryInfoWithContext(ctx)
		if err != nil || mi == nil {
			continue
		}
		name, err := p.NameWithContext(ctx)
		if err != nil {
			continue
		}
		rows = append(rows, procRow{Name: trimExe(name), PID: p.Pid, Value: float64(mi.RSS) * 100 / float64(totalBytes)})
	}
	return rows
}

// buildTopCard renders a "Processes" card: one key per process name with the
// percentage as value, "name (PID)" as label, ordered from firstOrder in steps
// of 10, highest first. Cards are ephemeral: no timestamp, no status_since.
func (e *Env) buildTopCard(name, title string, firstOrder int, rows []rankedProc, status string) writer.Output {
	st := e.newEphemeral("lucide/rows-4", e.T(title), OrderTop)
	for i, r := range rows {
		st.AddField(state.Field{
			Key:   processKey(r.Name),
			Value: fmt.Sprintf("%.1f", r.Value),
			Label: procLabel(r),
			Order: firstOrder + 10*i,
			Unit:  "%",
		})
	}
	st.Set("status", status)
	return writer.Output{Name: name, State: st, TimerTotal: 2}
}
