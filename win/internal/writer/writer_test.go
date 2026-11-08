package writer

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"syswatch-win/internal/history"
	"syswatch-win/internal/state"
)

func newTestWriter(t *testing.T) (*Writer, string) {
	dir := t.TempDir()
	w := New(history.New())
	w.Configure(dir, "HOGAR-PC.local", time.Second)
	return w, dir
}

func sampleOutput() Output {
	st := state.New()
	st.Set("usage", "12")
	return Output{Name: "cpu", State: st, Series: map[string]int64{"usage": 12}, IntervalS: 60, CSVPoints: 30}
}

func TestSubmitRefusesWithoutImportMarker(t *testing.T) {
	w, dir := newTestWriter(t)
	if err := w.Submit(sampleOutput()); err != ErrNotReady {
		t.Fatalf("want ErrNotReady, got %v", err)
	}
	entries, _ := os.ReadDir(dir)
	if len(entries) != 0 {
		t.Fatalf("nothing may be written without .import, found %d entries", len(entries))
	}
}

func TestSubmitWritesAllFilesWithLF(t *testing.T) {
	w, dir := newTestWriter(t)
	os.WriteFile(filepath.Join(dir, ".import"), nil, 0o644)
	if err := w.Submit(sampleOutput()); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"cpu-HOGAR-PC.state", "cpu-HOGAR-PC.timer", "cpu-HOGAR-PC.usage.csv"} {
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if strings.Contains(string(b), "\r") {
			t.Errorf("%s contains CR", name)
		}
	}
	timer, _ := os.ReadFile(filepath.Join(dir, "cpu-HOGAR-PC.timer"))
	if string(timer) != "cpu-HOGAR-PC=TOTAL:6|ACTION:deletestate|COUNT:6\n" {
		t.Errorf("timer = %q", timer)
	}
	csv, _ := os.ReadFile(filepath.Join(dir, "cpu-HOGAR-PC.usage.csv"))
	lines := strings.Split(strings.TrimSpace(string(csv)), "\n")
	if lines[0] != "timestamp,value" || len(lines) != 2 || !strings.HasSuffix(lines[1], ",12") {
		t.Errorf("csv = %q", csv)
	}
	// no temporary files left behind
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".tmp") {
			t.Errorf("leftover temp file %s", e.Name())
		}
	}
}

func TestHistoryKeepsSamplesWhileNotReady(t *testing.T) {
	w, dir := newTestWriter(t)
	for i := 0; i < 3; i++ {
		_ = w.Submit(sampleOutput()) // not ready: only memory
	}
	w.checkedAt = time.Time{} // drop the cached "not ready"
	os.WriteFile(filepath.Join(dir, ".import"), nil, 0o644)
	if err := w.Submit(sampleOutput()); err != nil {
		t.Fatal(err)
	}
	csv, _ := os.ReadFile(filepath.Join(dir, "cpu-HOGAR-PC.usage.csv"))
	if n := strings.Count(string(csv), "\n"); n != 5 { // header + 4 points
		t.Errorf("want header+4 points, got %d lines:\n%s", n, csv)
	}
}

func TestSeedFromExistingCSV(t *testing.T) {
	w, dir := newTestWriter(t)
	os.WriteFile(filepath.Join(dir, ".import"), nil, 0o644)
	os.WriteFile(filepath.Join(dir, "cpu-HOGAR-PC.usage.csv"), []byte("timestamp,value\n100,1\n200,2\n"), 0o644)
	if err := w.Submit(sampleOutput()); err != nil {
		t.Fatal(err)
	}
	csv, _ := os.ReadFile(filepath.Join(dir, "cpu-HOGAR-PC.usage.csv"))
	if !strings.Contains(string(csv), "100,1\n200,2\n") {
		t.Errorf("old points lost: %s", csv)
	}
}

func TestRemoveDeletesEverything(t *testing.T) {
	w, dir := newTestWriter(t)
	os.WriteFile(filepath.Join(dir, ".import"), nil, 0o644)
	if err := w.Submit(sampleOutput()); err != nil {
		t.Fatal(err)
	}
	if err := w.Remove("cpu"); err != nil {
		t.Fatal(err)
	}
	entries, _ := os.ReadDir(dir)
	if len(entries) != 1 || entries[0].Name() != ".import" {
		t.Errorf("unexpected files left: %v", entries)
	}
}

func TestSafeHostAndSlug(t *testing.T) {
	cases := map[string]string{"HOGAR-PC.local": "HOGAR-PC", "my pc": "my-pc", "": "host", "ñandú": "and"}
	for in, want := range cases {
		if got := SafeHost(in); got != want {
			t.Errorf("SafeHost(%q) = %q, want %q", in, got, want)
		}
	}
	slugs := map[string]string{"Wi-Fi": "wi_fi", "vEthernet (WSL)": "vethernet_wsl", "Ethernet 2": "ethernet_2", "C:": "c"}
	for in, want := range slugs {
		if got := Slug(in); got != want {
			t.Errorf("Slug(%q) = %q, want %q", in, got, want)
		}
	}
}
