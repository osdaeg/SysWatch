// Package app wires config, collectors, scheduler and writer together.
package app

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"syswatch-win/internal/collector"
	"syswatch-win/internal/config"
	"syswatch-win/internal/history"
	"syswatch-win/internal/i18n"
	"syswatch-win/internal/store"
	"syswatch-win/internal/writer"
)

// Status is a snapshot for the tray.
type Status struct {
	Configured bool
	Paused     bool
	NotReady   bool // .import missing or folder unreachable
	LastWrite  time.Time
	ConfigErr  string
}

// App owns the running modules.
type App struct {
	cfgPath string
	cfgDir  string
	log     *log.Logger
	tr      *i18n.Translator
	wr      *writer.Writer
	st      *store.Store

	mu        sync.Mutex
	cfg       *config.Config
	cfgMTime  time.Time
	cfgErr    string
	firstRun  bool
	cancel    context.CancelFunc
	wg        sync.WaitGroup
	watchCtx  context.Context
	stopWatch context.CancelFunc

	// OnConfig, if set, runs after every (re)load with the active settings.
	OnConfig func(*config.Config)

	paused    atomic.Bool
	ready     atomic.Int32 // 0 unknown, 1 ready, 2 not ready
	lastWrite atomic.Int64
}

// New creates an App for the settings file at cfgPath.
func New(cfgPath string, logger *log.Logger) *App {
	dir := filepath.Dir(cfgPath)
	return &App{
		cfgPath: cfgPath,
		cfgDir:  dir,
		log:     logger,
		tr:      i18n.New(),
		wr:      writer.New(history.New()),
		st:      store.Open(filepath.Join(dir, "runtime.json")),
	}
}

// Translator exposes the active translator (for the tray).
func (a *App) Translator() *i18n.Translator { return a.tr }

// ConfigPath returns the settings file path.
func (a *App) ConfigPath() string { return a.cfgPath }

// FirstRun reports that the settings file did not exist and was just created.
func (a *App) FirstRun() bool { return a.firstRun }

// Config returns the active settings.
func (a *App) Config() *config.Config {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.cfg
}

// Start loads the settings and launches the modules.
func (a *App) Start() error {
	cfg, created, err := config.Load(a.cfgPath)
	if err != nil {
		a.log.Printf("settings error: %v (using defaults)", err)
		a.cfgErr = err.Error()
		cfg = config.Default()
	}
	if created {
		a.firstRun = true
		if err := config.Save(a.cfgPath, cfg); err != nil {
			a.log.Printf("cannot create settings file: %v", err)
		}
	}
	a.noteMTime()
	a.apply(cfg)
	a.watchCtx, a.stopWatch = context.WithCancel(context.Background())
	go a.watch(a.watchCtx)
	return nil
}

func (a *App) noteMTime() {
	if fi, err := os.Stat(a.cfgPath); err == nil {
		a.cfgMTime = fi.ModTime()
	}
}

// Reload re-reads the settings; on error the running configuration is kept.
func (a *App) Reload() error {
	cfg, _, err := config.Load(a.cfgPath)
	if err != nil {
		a.mu.Lock()
		a.cfgErr = err.Error()
		a.mu.Unlock()
		a.log.Printf("settings reload failed: %v", err)
		return err
	}
	a.mu.Lock()
	a.cfgErr = ""
	a.mu.Unlock()
	a.noteMTime()
	a.apply(cfg)
	return nil
}

func (a *App) watch(ctx context.Context) {
	t := time.NewTicker(5 * time.Second)
	defer t.Stop()
	flush := time.NewTicker(30 * time.Second)
	defer flush.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-flush.C:
			_ = a.st.Flush(false)
		case <-t.C:
			if fi, err := os.Stat(a.cfgPath); err == nil && !fi.ModTime().Equal(a.cfgMTime) {
				a.log.Printf("settings changed, reloading")
				_ = a.Reload()
			}
		}
	}
}

func hostDisplay(cfg *config.Config) string {
	h := cfg.Hostname
	if h == "" {
		h, _ = os.Hostname()
		if i := strings.IndexByte(h, '.'); i > 0 {
			h = h[:i]
		}
	}
	if h == "" {
		h = "host"
	}
	return h
}

// apply (re)starts every enabled module with cfg.
func (a *App) apply(cfg *config.Config) {
	a.stopModules()

	lang := cfg.Language
	if lang == "" {
		lang = i18n.DetectLang()
	}
	a.tr.LoadDir(filepath.Join(a.cfgDir, "lang"))
	a.tr.SetLang(lang)

	host := hostDisplay(cfg)
	a.wr.Configure(cfg.OutputDir, host, time.Duration(cfg.ImportTimeoutS)*time.Second)
	a.ready.Store(0)

	ctx, cancel := context.WithCancel(context.Background())
	a.mu.Lock()
	a.cfg = cfg
	a.cancel = cancel
	a.mu.Unlock()

	for _, name := range config.ModuleNames {
		mod := cfg.Module(name)
		if !mod.Enabled {
			continue
		}
		env := &collector.Env{Cfg: cfg, Mod: mod, Host: host, T: a.tr.T, Store: a.st, Now: time.Now}
		col := collector.New(name, env)
		if col == nil {
			continue
		}
		a.wg.Add(1)
		go a.run(ctx, env, col)
	}
	a.log.Printf("started: output=%q host=%q lang=%q", cfg.OutputDir, host, lang)
	if a.OnConfig != nil {
		a.OnConfig(cfg)
	}
}

func (a *App) stopModules() {
	a.mu.Lock()
	cancel := a.cancel
	a.cancel = nil
	a.mu.Unlock()
	if cancel != nil {
		cancel()
		done := make(chan struct{})
		go func() { a.wg.Wait(); close(done) }()
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			a.log.Printf("warning: modules did not stop within 5s")
		}
	}
}

// Stop halts everything and saves runtime data.
func (a *App) Stop() {
	if a.stopWatch != nil {
		a.stopWatch()
	}
	a.stopModules()
	_ = a.st.Flush(true)
}

// SetPaused pauses or resumes all collection.
func (a *App) SetPaused(p bool) { a.paused.Store(p) }

// Paused reports the pause state.
func (a *App) Paused() bool { return a.paused.Load() }

// Status returns a snapshot for the tray.
func (a *App) Status() Status {
	a.mu.Lock()
	cfg, cfgErr := a.cfg, a.cfgErr
	a.mu.Unlock()
	s := Status{Paused: a.paused.Load(), NotReady: a.ready.Load() == 2, ConfigErr: cfgErr}
	if cfg != nil {
		s.Configured = cfg.OutputDir != ""
	}
	if t := a.lastWrite.Load(); t > 0 {
		s.LastWrite = time.Unix(t, 0)
	}
	return s
}

func (a *App) run(ctx context.Context, env *collector.Env, col collector.Collector) {
	defer a.wg.Done()
	interval := time.Duration(env.Mod.IntervalS) * time.Second
	tick := time.NewTicker(interval)
	defer tick.Stop()
	for {
		a.cycle(ctx, env, col, interval)
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
	}
}

func (a *App) cycle(ctx context.Context, env *collector.Env, col collector.Collector, interval time.Duration) {
	if a.paused.Load() || ctx.Err() != nil {
		return
	}
	var res collector.Result
	func() {
		defer func() {
			if r := recover(); r != nil {
				a.log.Printf("%s: panic: %v", col.Name(), r)
				res = collector.Result{Outputs: []writer.Output{env.Fallback(col.Name(), col.Meta())}}
			}
		}()
		cctx, cancel := context.WithTimeout(ctx, interval)
		defer cancel()
		r, err := col.Collect(cctx)
		if err != nil {
			a.log.Printf("%s: %v", col.Name(), err)
			r = collector.Result{Outputs: []writer.Output{env.Fallback(col.Name(), col.Meta())}}
		}
		res = r
	}()
	for _, o := range res.Outputs {
		a.report(col.Name(), a.wr.Submit(o))
	}
	for _, name := range res.Remove {
		if err := a.wr.Remove(name); err != nil && !errors.Is(err, writer.ErrNotReady) {
			a.log.Printf("%s: remove %s: %v", col.Name(), name, err)
		}
	}
}

func (a *App) report(module string, err error) {
	switch {
	case err == nil:
		if a.ready.Swap(1) == 2 {
			a.log.Printf("output folder is back (.import found)")
		}
		a.lastWrite.Store(time.Now().Unix())
	case errors.Is(err, writer.ErrNotReady):
		if a.ready.Swap(2) != 2 {
			a.log.Printf("output folder not ready: %s\\%s missing or unreachable; collecting without writing", a.wr.Dir(), writer.ImportMarker)
		}
	default:
		a.log.Printf("%s: write failed: %v", module, fmt.Sprint(err))
	}
}
