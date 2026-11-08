package config

import (
	"encoding/json"
	"testing"
)

func TestPartialJSONKeepsDefaults(t *testing.T) {
	var c Config
	err := json.Unmarshal([]byte(`{"output_dir":"\\\\srv\\import","modules":{"cpu":{"interval_s":2,"csv_points":5},"disk":{"enabled":false}}}`), &c)
	if err != nil {
		t.Fatal(err)
	}
	c.Validate()
	if c.OutputDir != `\\srv\import` || !c.Autostart || c.ImportTimeoutS != 3 {
		t.Errorf("top-level defaults lost: %+v", c)
	}
	cpu := c.Module("cpu")
	if cpu.IntervalS != MinIntervalS || cpu.CSVPoints != MinCSVPoints || !cpu.Enabled || !cpu.TopProcesses {
		t.Errorf("cpu = %+v", cpu)
	}
	if c.Module("disk").Enabled || c.Module("disk").IntervalS != 300 {
		t.Errorf("disk = %+v", c.Module("disk"))
	}
	if !c.Module("network").IncludeTotal || c.Module("network").CSVPoints != 30 {
		t.Errorf("network defaults lost: %+v", c.Module("network"))
	}
}
