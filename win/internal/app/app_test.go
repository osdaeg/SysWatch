package app

import (
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func writeConfig(t *testing.T, dir, out string) string {
	cfg := `{"output_dir":` + quote(out) + `,"hostname":"TEST-PC","language":"es","import_timeout_s":1,
	"modules":{"cpu":{"interval_s":5,"top_processes":false},"memory":{"interval_s":5,"top_processes":false},
	"disk":{"enabled":false},"smart":{"enabled":false},"about":{"enabled":false},"network":{"enabled":false}}}`
	p := filepath.Join(dir, "config.json")
	if err := os.WriteFile(p, []byte(cfg), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func quote(s string) string { return `"` + strings.ReplaceAll(s, `\`, `\\`) + `"` }

func waitFor(t *testing.T, path string, d time.Duration) bool {
	end := time.Now().Add(d)
	for time.Now().Before(end) {
		if _, err := os.Stat(path); err == nil {
			return true
		}
		time.Sleep(100 * time.Millisecond)
	}
	return false
}

func TestEndToEndWritesAndRespectsImportMarker(t *testing.T) {
	cfgDir, out := t.TempDir(), t.TempDir()
	a := New(writeConfig(t, cfgDir, out), log.New(io.Discard, "", 0))
	if err := a.Start(); err != nil {
		t.Fatal(err)
	}
	defer a.Stop()

	// without .import: nothing may appear
	time.Sleep(1500 * time.Millisecond)
	if entries, _ := os.ReadDir(out); len(entries) != 0 {
		t.Fatalf("files written without .import: %v", entries)
	}
	if !a.Status().NotReady {
		t.Error("status should report not ready")
	}

	// create .import: the next cycle (<=5s) must write
	os.WriteFile(filepath.Join(out, ".import"), nil, 0o644)
	if !waitFor(t, filepath.Join(out, "cpu-TEST-PC.state"), 9*time.Second) {
		t.Fatal("cpu state never appeared")
	}
	if !waitFor(t, filepath.Join(out, "memory-TEST-PC.state"), 3*time.Second) {
		t.Fatal("memory state never appeared")
	}
	for _, f := range []string{"cpu-TEST-PC.timer", "cpu-TEST-PC.usage.csv"} {
		if _, err := os.Stat(filepath.Join(out, f)); err != nil {
			t.Errorf("missing %s", f)
		}
	}
	b, _ := os.ReadFile(filepath.Join(out, "cpu-TEST-PC.state"))
	if !strings.Contains(string(b), "usage.label=Uso\n") || !strings.Contains(string(b), "sw_hostname=TEST-PC\n") {
		t.Errorf("unexpected state:\n%s", b)
	}
	if st := a.Status(); st.NotReady || st.LastWrite.IsZero() {
		t.Errorf("status = %+v", st)
	}
}

func TestPauseStopsWriting(t *testing.T) {
	cfgDir, out := t.TempDir(), t.TempDir()
	os.WriteFile(filepath.Join(out, ".import"), nil, 0o644)
	a := New(writeConfig(t, cfgDir, out), log.New(io.Discard, "", 0))
	a.SetPaused(true)
	if err := a.Start(); err != nil {
		t.Fatal(err)
	}
	defer a.Stop()
	time.Sleep(1500 * time.Millisecond)
	if entries, _ := os.ReadDir(out); len(entries) != 1 { // only .import
		t.Fatalf("paused app wrote files: %v", entries)
	}
}
