package history

import (
	"strings"
	"testing"
)

func TestTrimsAndNeverBelowEleven(t *testing.T) {
	h := New()
	for i := 0; i < 50; i++ {
		h.Add("k", int64(i), int64(i), 3) // 3 is clamped up to 11
	}
	if h.Len("k") != MinPoints {
		t.Errorf("len = %d", h.Len("k"))
	}
	lines := strings.Split(strings.TrimSpace(string(h.CSV("k"))), "\n")
	if lines[0] != "timestamp,value" || lines[1] != "39,39" || lines[len(lines)-1] != "49,49" {
		t.Errorf("csv = %v", lines)
	}
}

func TestSeedOnlyOlderPoints(t *testing.T) {
	h := New()
	h.Add("k", 100, 5, 30)
	h.Seed("k", strings.NewReader("timestamp,value\n10,1\n20,2\n100,9\n"), 30)
	got := string(h.CSV("k"))
	if got != "timestamp,value\n10,1\n20,2\n100,5\n" {
		t.Errorf("got %q", got)
	}
	if !h.Seeded("k") {
		t.Error("not marked seeded")
	}
}
