package collector

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"syswatch-win/internal/config"
	"syswatch-win/internal/i18n"
	"syswatch-win/internal/state"
	"syswatch-win/internal/store"
)

func testEnv(t *testing.T, module string) *Env {
	cfg := config.Default()
	tr := i18n.New()
	tr.SetLang("es")
	return &Env{
		Cfg: cfg, Mod: cfg.Module(module), Host: "TEST-PC", T: tr.T,
		Store: store.Open(filepath.Join(t.TempDir(), "runtime.json")), Now: time.Now,
	}
}

func get(t *testing.T, st *state.State, key string) string {
	v, ok := st.Get(key)
	if !ok {
		t.Fatalf("missing key %q in:\n%s", key, st.Bytes())
	}
	return v
}

func TestCPUState(t *testing.T) {
	env := testEnv(t, "cpu")
	env.Mod.TopProcesses = false
	res, err := NewCPU(env).Collect(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Outputs) != 1 {
		t.Fatalf("want 1 output, got %d", len(res.Outputs))
	}
	o := res.Outputs[0]
	if o.Name != "cpu" {
		t.Errorf("name = %s", o.Name)
	}
	st := o.State
	if get(t, st, "usage.widget") != "line" || get(t, st, "usage.label") != "Uso" {
		t.Errorf("usage keys wrong:\n%s", st.Bytes())
	}
	if get(t, st, "cores.label") != "Núcleos" || get(t, st, "module.order") != "30" {
		t.Errorf("cores/module keys wrong:\n%s", st.Bytes())
	}
	if get(t, st, "sw_hostname.hidden") != "false" || get(t, st, "sw_hostname") != "TEST-PC" {
		t.Errorf("host block wrong")
	}
	if _, ok := o.Series["usage"]; !ok {
		t.Errorf("no usage series")
	}
	if o.CSVPoints != 30 {
		t.Errorf("csv points = %d", o.CSVPoints)
	}
	if get(t, st, "status") == "" || get(t, st, "status_since") == "" || get(t, st, "timestamp") == "" {
		t.Errorf("status/timestamp missing")
	}
}

func TestMemoryState(t *testing.T) {
	env := testEnv(t, "memory")
	env.Mod.TopProcesses = false
	res, err := NewMemory(env).Collect(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	st := res.Outputs[0].State
	for _, k := range []string{"usage", "total_mb", "used_mb", "available_mb"} {
		get(t, st, k)
	}
	if get(t, st, "usage.widget") != "gauge" || get(t, st, "usage.warning") != "80" || get(t, st, "usage.critical") != "95" {
		t.Errorf("memory thresholds wrong:\n%s", st.Bytes())
	}
	if len(res.Outputs[0].Series) != 0 {
		t.Errorf("gauge must not produce csv")
	}
}

func TestDiskStates(t *testing.T) {
	env := testEnv(t, "disk")
	res, err := NewDisk(env).Collect(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Outputs) == 0 {
		t.Skip("no volumes in this environment")
	}
	st := res.Outputs[0].State
	if !strings.HasPrefix(res.Outputs[0].Name, "disk_") || get(t, st, "used_pct.widget") != "gauge" {
		t.Errorf("unexpected disk state:\n%s", st.Bytes())
	}
	if get(t, st, "used_pct.warning") != "85" || get(t, st, "mountpoint.hidden") != "true" || get(t, st, "total.render") != "bytes" {
		t.Errorf("disk keys wrong:\n%s", st.Bytes())
	}
}

func TestNetworkStates(t *testing.T) {
	env := testEnv(t, "network")
	c := NewNetwork(env)
	if _, err := c.Collect(context.Background()); err != nil {
		t.Fatal(err)
	}
	time.Sleep(1100 * time.Millisecond)
	res, err := c.Collect(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, o := range res.Outputs {
		if _, ok := o.State.Get("status"); !ok {
			t.Errorf("%s has no status", o.Name)
		}
		if st, _ := o.State.Get("status"); st == state.OK {
			if o.State.Len() == 0 || o.Series["down"] < 0 {
				t.Errorf("bad series for %s", o.Name)
			}
			if v, _ := o.State.Get("down.widget"); v != "line" {
				t.Errorf("down must be a line widget")
			}
		}
	}
}

func TestAboutState(t *testing.T) {
	env := testEnv(t, "about")
	res, err := NewAbout(env).Collect(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	get(t, res.Outputs[0].State, "memory_total")
}

func TestRankByNameAndKeys(t *testing.T) {
	rows := []procRow{{"chrome", 1.5}, {"chrome", 2.0}, {"bash", 3.0}, {"idle", 0}, {"a", 0.1}}
	top := rankByName(rows, 2)
	if len(top) != 2 || top[0].Name != "chrome" || top[0].Value != 3.5 || top[1].Name != "bash" {
		t.Errorf("rank = %+v", top)
	}
	if processKey("Microsoft Edge") != "Microsoft_Edge" || trimExe("Code.EXE") != "Code" || trimExe("openvpn2.5") != "openvpn2.5" {
		t.Errorf("name helpers wrong")
	}
}

func TestTopCardFormatMatchesLinux(t *testing.T) {
	env := testEnv(t, "cpu")
	rows := []procRow{{"bash", 1.8}, {"openvpn2.5", 1.6}}
	o := env.buildTopCard("cpu_top", rows, "%", state.Warning, func(v float64) string { return sprintf1(v) })
	st := o.State
	if get(t, st, "bash") != "1.8" || get(t, st, "bash.order") != "70" || get(t, st, "openvpn2.5.order") != "80" || get(t, st, "bash.unit") != "%" {
		t.Errorf("top card keys wrong:\n%s", st.Bytes())
	}
	if get(t, st, "module.order") != "900" || get(t, st, "module.icon") != "lucide/rows-4" || get(t, st, "status") != "WARNING" {
		t.Errorf("top module keys wrong")
	}
	if _, ok := st.Get("timestamp"); ok {
		t.Errorf("top card must not have timestamp")
	}
	if _, ok := st.Get("status_since"); ok {
		t.Errorf("top card must not have status_since")
	}
	if o.TimerTotal != 2 {
		t.Errorf("timer total = %d", o.TimerTotal)
	}
}
