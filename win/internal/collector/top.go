package collector

import (
	"context"
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

// procRow is one process observation.
type procRow struct {
	Name  string
	Value float64
}

// rankByName sums rows that share a name, drops zero values and returns the
// top n by value, descending (ties broken by name so output is stable).
func rankByName(rows []procRow, n int) []procRow {
	sum := map[string]float64{}
	for _, r := range rows {
		if r.Name == "" {
			continue
		}
		sum[r.Name] += r.Value
	}
	out := make([]procRow, 0, len(sum))
	for name, v := range sum {
		if v > 0 {
			out = append(out, procRow{name, v})
		}
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

// Sample returns CPU % per process name since the previous call, normalized by
// the number of logical cores so it compares with the overall usage. Processes
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
		rows = append(rows, procRow{Name: trimExe(name), Value: pct})
	}
	s.prev, s.prevTime = cur, now
	return rows
}

// memoryRows lists resident memory (working set on Windows) in Mb per name.
func memoryRows(ctx context.Context) []procRow {
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
		rows = append(rows, procRow{Name: trimExe(name), Value: float64(mi.RSS) / (1024 * 1024)})
	}
	return rows
}

// buildTopCard renders the "Processes" card shared by cpu and memory.
// values are formatted with format("%.1f" for CPU, integer Mb for memory).
func (e *Env) buildTopCard(name string, rows []procRow, unit, status string, format func(float64) string) writer.Output {
	st := e.newEphemeral("lucide/rows-4", e.T("Processes"), OrderTop)
	for i, r := range rows {
		k := processKey(r.Name)
		st.AddField(state.Field{
			Key:   k,
			Value: format(r.Value),
			Label: r.Name,
			Order: 70 + 10*i,
			Unit:  unit,
		})
	}
	st.Set("status", status)
	return writer.Output{Name: name, State: st, TimerTotal: 2}
}
