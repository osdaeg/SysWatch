package state

import (
	"strings"
	"testing"
)

func TestSanitizeMatchesShellFunction(t *testing.T) {
	cases := map[string]string{
		"a\r\nb\tc":       "a b c",
		"Intel(R)   Core": "Intel(R) Core",
		"ok":              "ok",
		"  x  ":           " x ", // tr -s squeezes but never trims
	}
	for in, want := range cases {
		if got := Sanitize(in); got != want {
			t.Errorf("Sanitize(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestBytesSortedLFOnly(t *testing.T) {
	s := New()
	s.AddField(Field{Key: "load15", Value: "6.01", Label: "x", Order: 40})
	s.AddField(Field{Key: "load1", Value: "0.44", Label: "y", Order: 20})
	s.Set("Prowlarr", "1.2")
	s.Set("_internal.mountpoint", "/home")
	s.Set("avail", "1")
	got := string(s.Bytes())
	if strings.Contains(got, "\r") {
		t.Fatal("CR in output")
	}
	want := "Prowlarr=1.2\n_internal.mountpoint=/home\navail=1\nload1=0.44\nload1.label=y\nload1.order=20\nload15=6.01\nload15.label=x\nload15.order=40\n"
	if got != want {
		t.Errorf("got:\n%s\nwant:\n%s", got, want)
	}
}

func TestLevelAndWorst(t *testing.T) {
	if Level(79.9, 80, 95) != OK || Level(80, 80, 95) != Warning || Level(95, 80, 95) != Critical {
		t.Error("thresholds must be >=")
	}
	if Worst(OK, Critical) != Critical || Worst(Warning, OK) != Warning {
		t.Error("Worst wrong")
	}
}
