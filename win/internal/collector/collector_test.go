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
	rows := []procRow{{"chrome", 10, 1.5}, {"chrome", 11, 2.0}, {"bash", 20, 3.0}, {"idle", 1, 0}, {"a", 2, 0.1}}
	top := rankByName(rows, 2)
	if len(top) != 2 || top[0].Name != "chrome" || top[0].Value != 3.5 || top[0].N != 2 || top[0].PID != 11 || top[1].Name != "bash" {
		t.Errorf("rank = %+v", top)
	}
	if procLabel(top[0]) != "chrome (×2)" || procLabel(top[1]) != "bash (20)" {
		t.Errorf("labels: %q %q", procLabel(top[0]), procLabel(top[1]))
	}
	if processKey("Microsoft Edge") != "Microsoft_Edge" || trimExe("Code.EXE") != "Code" || trimExe("openvpn2.5") != "openvpn2.5" {
		t.Errorf("name helpers wrong")
	}
}

func TestTopCardFormatMatchesLinux(t *testing.T) {
	env := testEnv(t, "memory")
	rows := []rankedProc{{"stress-ng-vm", 3872810, 1, 26.6}, {"Sonarr", 50073, 1, 2.1}, {"chrome", 5, 12, 1.2}}
	o := env.buildTopCard("memory_top", "Processes (memory)", 50, rows, state.Warning)
	st := o.State
	if get(t, st, "stress-ng-vm") != "26.6" || get(t, st, "stress-ng-vm.label") != "stress-ng-vm (3872810)" ||
		get(t, st, "stress-ng-vm.order") != "50" || get(t, st, "Sonarr.order") != "60" || get(t, st, "stress-ng-vm.unit") != "%" {
		t.Errorf("top card keys wrong:\n%s", st.Bytes())
	}
	if get(t, st, "chrome.label") != "chrome (×12)" {
		t.Errorf("grouped label wrong")
	}
	if get(t, st, "module.label") != "Procesos en memoria" || get(t, st, "module.order") != "900" ||
		get(t, st, "module.icon") != "lucide/rows-4" || get(t, st, "status") != "WARNING" {
		t.Errorf("top module keys wrong:\n%s", st.Bytes())
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

func TestLoadEstimatorTracksBusyCores(t *testing.T) {
	l := newLoadEstimator(12)
	for i := 0; i < 360; i++ { // 30 minutes of 5 s samples at 50% of 12 cores
		l.add(50, 5)
	}
	l1, l5, l15, ok := l.loads()
	if !ok || l1 < 5.9 || l1 > 6.1 || l5 < 5.9 || l15 < 5.9 {
		t.Errorf("steady 50%% of 12 cores should give ~6.0, got %.2f %.2f %.2f", l1, l5, l15)
	}
	for i := 0; i < 24; i++ { // 2 minutes idle: the 1-minute average falls faster than the 15-minute one
		l.add(0, 5)
	}
	a, _, c, _ := l.loads()
	if !(a < 1.5 && c > 4.5 && a < c) {
		t.Errorf("after 2 idle minutes l1=%.2f l15=%.2f", a, c)
	}
	if v, ok := l.takeUsage(); !ok || v < 40 || v > 50 {
		t.Errorf("average usage = %.1f", v)
	}
	if _, ok := l.takeUsage(); ok {
		t.Errorf("takeUsage must reset")
	}
}

func TestConfiguredOrder(t *testing.T) {
	env := testEnv(t, "cpu")
	env.Mod.TopProcesses = false
	env.Mod.Order = 33
	res, err := NewCPU(env).Collect(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if get(t, res.Outputs[0].State, "module.order") != "33" {
		t.Errorf("order override ignored")
	}
}

func TestDecideConnectedAndTrimBuild(t *testing.T) {
	if decideConnected("OK", 0, 0, false) {
		t.Error("nothing says connected")
	}
	for _, c := range []bool{decideConnected("Up", 0, 0, false), decideConnected("", 1, 0, false), decideConnected("", 0, 1, false), decideConnected("OK", 0, 0, true)} {
		if !c {
			t.Error("one positive signal must be enough")
		}
	}
	if trimBuild("10.0.19045.6466 Build 19045.6466") != "10.0.19045.6466" || trimBuild("6.1") != "6.1" {
		t.Error("trimBuild wrong")
	}
}
