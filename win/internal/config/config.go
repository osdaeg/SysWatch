// Package config loads, validates and saves syswatch.exe's JSON settings.
package config

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

// Limits.
const (
	MinIntervalS = 5
	MinCSVPoints = 11
	DirName      = "syswatch-win"
	FileName     = "config.json"
)

// Module holds per-module settings. Fields that do not apply to a module are
// simply ignored by it.
type Module struct {
	Enabled          bool `json:"enabled"`
	IntervalS        int  `json:"interval_s"`
	CSVPoints        int  `json:"csv_points,omitempty"`
	TopProcesses     bool `json:"top_processes,omitempty"`
	IncludeRemovable bool `json:"include_removable,omitempty"`
	IncludeNetwork   bool `json:"include_network,omitempty"`
	IncludeVirtual   bool `json:"include_virtual,omitempty"`
	IncludeTotal     bool `json:"include_total,omitempty"`
}

// Config is the whole settings file.
type Config struct {
	OutputDir      string             `json:"output_dir"`
	Hostname       string             `json:"hostname"`
	Language       string             `json:"language"`
	ImportTimeoutS int                `json:"import_timeout_s"`
	Autostart      bool               `json:"autostart"`
	Modules        map[string]*Module `json:"modules"`
}

// ModuleNames lists known modules in a stable order.
var ModuleNames = []string{"cpu", "memory", "disk", "smart", "about", "network"}

// Default returns the default configuration.
func Default() *Config {
	return &Config{
		ImportTimeoutS: 3,
		Autostart:      true,
		Modules: map[string]*Module{
			"cpu":     {Enabled: true, IntervalS: 60, CSVPoints: 30, TopProcesses: true},
			"memory":  {Enabled: true, IntervalS: 60, TopProcesses: true},
			"disk":    {Enabled: true, IntervalS: 300},
			"smart":   {Enabled: true, IntervalS: 600},
			"about":   {Enabled: true, IntervalS: 3600},
			"network": {Enabled: true, IntervalS: 60, CSVPoints: 30, IncludeTotal: true},
		},
	}
}

// UnmarshalJSON decodes onto the defaults so absent keys keep their default,
// including inside each module.
func (c *Config) UnmarshalJSON(data []byte) error {
	def := Default()
	aux := struct {
		OutputDir      *string                    `json:"output_dir"`
		Hostname       *string                    `json:"hostname"`
		Language       *string                    `json:"language"`
		ImportTimeoutS *int                       `json:"import_timeout_s"`
		Autostart      *bool                      `json:"autostart"`
		Modules        map[string]json.RawMessage `json:"modules"`
	}{}
	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}
	if aux.OutputDir != nil {
		def.OutputDir = *aux.OutputDir
	}
	if aux.Hostname != nil {
		def.Hostname = *aux.Hostname
	}
	if aux.Language != nil {
		def.Language = *aux.Language
	}
	if aux.ImportTimeoutS != nil {
		def.ImportTimeoutS = *aux.ImportTimeoutS
	}
	if aux.Autostart != nil {
		def.Autostart = *aux.Autostart
	}
	for name, raw := range aux.Modules {
		m := def.Modules[name]
		if m == nil {
			m = &Module{Enabled: true, IntervalS: 60}
			def.Modules[name] = m
		}
		if err := json.Unmarshal(raw, m); err != nil {
			return err
		}
	}
	*c = *def
	return nil
}

// Validate clamps values to their allowed ranges.
func (c *Config) Validate() {
	if c.ImportTimeoutS < 1 {
		c.ImportTimeoutS = 3
	}
	for _, m := range c.Modules {
		if m.IntervalS < MinIntervalS {
			m.IntervalS = MinIntervalS
		}
		if m.CSVPoints != 0 && m.CSVPoints < MinCSVPoints {
			m.CSVPoints = MinCSVPoints
		}
	}
}

// Module returns the settings for a module (disabled if unknown).
func (c *Config) Module(name string) *Module {
	if m, ok := c.Modules[name]; ok {
		return m
	}
	return &Module{}
}

// Dir returns the settings directory (%APPDATA%\syswatch-win on Windows).
func Dir() (string, error) {
	base, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(base, DirName), nil
}

// Load reads path; a missing file yields the defaults and created=true.
func Load(path string) (cfg *Config, created bool, err error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return Default(), true, nil
	}
	if err != nil {
		return nil, false, err
	}
	cfg = &Config{}
	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, false, err
	}
	cfg.Validate()
	return cfg, false, nil
}

// Save writes the configuration as indented JSON.
func Save(path string, cfg *Config) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0o644)
}
