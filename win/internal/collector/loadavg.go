package collector

import (
	"context"
	"math"
	"sync"
	"time"
)

// loadEstimator replaces the Linux load average, which Windows lacks. It
// samples CPU usage every few seconds and keeps exponentially smoothed
// averages of "busy cores" (usage x logical cores) over 1, 5 and 15 minutes,
// which behaves like the Linux load for CPU-bound work. The same samples give
// the average usage between two reads, so short spikes are not missed.
type loadEstimator struct {
	mu      sync.Mutex
	cores   float64
	l1, l5  float64
	l15     float64
	primed  bool
	accSum  float64 // usage % x seconds since the last takeUsage
	accDt   float64
	running bool
}

func newLoadEstimator(cores int) *loadEstimator {
	if cores < 1 {
		cores = 1
	}
	return &loadEstimator{cores: float64(cores)}
}

// add feeds one usage sample (percent) that covers dt seconds.
func (l *loadEstimator) add(usagePct, dt float64) {
	if dt <= 0 {
		return
	}
	busy := usagePct / 100 * l.cores
	l.mu.Lock()
	defer l.mu.Unlock()
	if !l.primed {
		l.l1, l.l5, l.l15, l.primed = busy, busy, busy, true
	} else {
		l.l1 += (1 - math.Exp(-dt/60)) * (busy - l.l1)
		l.l5 += (1 - math.Exp(-dt/300)) * (busy - l.l5)
		l.l15 += (1 - math.Exp(-dt/900)) * (busy - l.l15)
	}
	l.accSum += usagePct * dt
	l.accDt += dt
}

// loads returns the three estimates (ok=false before the first sample).
func (l *loadEstimator) loads() (l1, l5, l15 float64, ok bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.l1, l.l5, l.l15, l.primed
}

// takeUsage returns the average usage since the previous call and resets it.
func (l *loadEstimator) takeUsage() (float64, bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.accDt <= 0 {
		return 0, false
	}
	v := l.accSum / l.accDt
	l.accSum, l.accDt = 0, 0
	return v, true
}

// run samples until ctx ends. sample must return the usage since its previous
// call (cpu.Percent with interval 0 does exactly that).
func (l *loadEstimator) run(ctx context.Context, every time.Duration, sample func(context.Context) (float64, error)) {
	l.mu.Lock()
	l.running = true
	l.mu.Unlock()
	_, _ = sample(ctx) // priming call
	last := time.Now()
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-t.C:
			if v, err := sample(ctx); err == nil {
				l.add(v, now.Sub(last).Seconds())
			}
			last = now
		}
	}
}

func (l *loadEstimator) isRunning() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.running
}
