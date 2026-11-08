package collector

import (
	"context"
	"sort"
	"sync"
	"time"

	"github.com/shirou/gopsutil/v3/net"

	"syswatch-win/internal/state"
	"syswatch-win/internal/writer"
)

type netSample struct {
	rx, tx uint64
	t      time.Time
}

// Network produces one state per adapter plus an optional aggregate.
type Network struct {
	env   *Env
	mu    sync.Mutex
	prev  map[string]netSample
	known map[string]bool
}

// NewNetwork creates the network collector.
func NewNetwork(env *Env) *Network {
	return &Network{env: env, prev: map[string]netSample{}, known: map[string]bool{}}
}

func (n *Network) Name() string { return "network" }
func (n *Network) Meta() Meta {
	return Meta{Icon: "lucide/network", Label: "Network", Order: OrderNetwork}
}

func rate(cur, prev uint64, dt float64) int64 {
	if dt <= 0 || cur < prev {
		return 0
	}
	return int64(float64(cur-prev) / dt)
}

func (n *Network) Collect(ctx context.Context) (Result, error) {
	e := n.env
	counters, err := net.IOCountersWithContext(ctx, true)
	if err != nil {
		return Result{}, err
	}
	byName := map[string]net.IOCountersStat{}
	for _, c := range counters {
		byName[c.Name] = c
	}
	ips := map[string]string{}
	if ifs, err := net.InterfacesWithContext(ctx); err == nil {
		for _, i := range ifs {
			ips[i.Name] = ipv4Of(i)
		}
	}
	infos := listAdapters(ctx)
	names := make([]string, 0, len(infos))
	for name := range infos {
		names = append(names, name)
	}
	sort.Strings(names)

	now := e.Now()
	n.mu.Lock()
	defer n.mu.Unlock()

	var res Result
	seen := map[string]bool{}
	var sumDown, sumUp int64
	var sumRx, sumTx uint64
	anyConnected := false

	for _, name := range names {
		info := infos[name]
		if !info.Physical && !e.Mod.IncludeVirtual {
			continue
		}
		stateName := writer.Slug(name)
		if stateName == "" || seen[stateName] {
			continue
		}
		seen[stateName] = true

		st := e.newState("lucide/network", name, OrderNetwork)
		c, haveCounters := byName[name]
		var totRx, totTx uint64
		if haveCounters {
			totRx, totTx = e.Store.NetTotals("net:"+name, c.BytesRecv, c.BytesSent)
		}
		out := writer.Output{Name: stateName, State: st, IntervalS: e.Mod.IntervalS, CSVPoints: e.Mod.CSVPoints}

		if !info.Connected || !haveCounters {
			delete(n.prev, name)
			e.setStatus(st, stateName, state.None)
			addNetTotals(e, st, totRx, totTx, haveCounters)
			res.Outputs = append(res.Outputs, out)
			continue
		}

		var down, up int64
		if p, ok := n.prev[name]; ok {
			dt := now.Sub(p.t).Seconds()
			down, up = rate(c.BytesRecv, p.rx, dt), rate(c.BytesSent, p.tx, dt)
		}
		n.prev[name] = netSample{rx: c.BytesRecv, tx: c.BytesSent, t: now}
		anyConnected = true
		sumDown, sumUp = sumDown+down, sumUp+up
		sumRx, sumTx = sumRx+totRx, sumTx+totTx

		addNetLines(e, st, down, up)
		if ip := ips[name]; ip != "" {
			st.AddField(state.Field{Key: "ip", Value: ip, Label: e.T("IP address"), Order: 30})
		}
		if mbps := info.SpeedBps / 1_000_000; mbps > 0 && mbps < 1_000_000 {
			st.AddField(state.Field{Key: "link_speed", Value: itoa(int64(mbps)), Label: e.T("Link speed"), Order: 40, Unit: "Mbps"})
		}
		addNetTotals(e, st, totRx, totTx, true)
		e.setStatus(st, stateName, state.OK)
		out.Series = map[string]int64{"down": down, "up": up}
		res.Outputs = append(res.Outputs, out)
	}

	if e.Mod.IncludeTotal && len(seen) > 0 {
		st := e.newState("lucide/network", e.T("All adapters"), OrderNetTot)
		out := writer.Output{Name: "network_total", State: st, IntervalS: e.Mod.IntervalS, CSVPoints: e.Mod.CSVPoints}
		if anyConnected {
			addNetLines(e, st, sumDown, sumUp)
			out.Series = map[string]int64{"down": sumDown, "up": sumUp}
			e.setStatus(st, "network_total", state.OK)
		} else {
			e.setStatus(st, "network_total", state.None)
		}
		addNetTotals(e, st, sumRx, sumTx, true)
		res.Outputs = append(res.Outputs, out)
		seen["network_total"] = true
	}

	for name := range n.known {
		if !seen[name] {
			res.Remove = append(res.Remove, name)
		}
	}
	n.known = seen
	return res, nil
}

func addNetLines(e *Env, st *state.State, down, up int64) {
	st.AddField(state.Field{Key: "down", Value: itoa(down), Label: e.T("Download"), Order: 10, Unit: "B/s", Widget: "line"})
	st.AddField(state.Field{Key: "up", Value: itoa(up), Label: e.T("Upload"), Order: 20, Unit: "B/s", Widget: "line"})
}

func addNetTotals(e *Env, st *state.State, rx, tx uint64, have bool) {
	if !have {
		return
	}
	st.AddField(state.Field{Key: "down_total", Value: itoa(int64(rx)), Label: e.T("Downloaded total"), Order: 50, Render: "bytes"})
	st.AddField(state.Field{Key: "up_total", Value: itoa(int64(tx)), Label: e.T("Uploaded total"), Order: 60, Render: "bytes"})
}
