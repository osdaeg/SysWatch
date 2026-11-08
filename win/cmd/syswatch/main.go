// syswatch.exe: tray-resident exporter of SysWatch .state/.timer/.csv files
// for Windows.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"syswatch-win/internal/app"
	"syswatch-win/internal/config"
	"syswatch-win/internal/logx"
	"syswatch-win/internal/platform"
	"syswatch-win/internal/tray"
)

// version is overridden at build time with -ldflags "-X main.version=...".
var version = "0.1.0"

func main() {
	cfgFlag := flag.String("config", "", "path to config.json (default: %APPDATA%\\syswatch-win\\config.json)")
	headless := flag.Bool("headless", false, "run without tray icon (development)")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()
	if *showVersion {
		fmt.Println("syswatch", version)
		return
	}

	cfgPath := *cfgFlag
	if cfgPath == "" {
		dir, err := config.Dir()
		if err != nil {
			fmt.Fprintln(os.Stderr, "cannot locate settings folder:", err)
			os.Exit(1)
		}
		cfgPath = filepath.Join(dir, config.FileName)
	}

	release, ok := platform.SingleInstance(`Local\syswatch-win`)
	if !ok {
		return // already running
	}
	defer release()

	logger := logx.New(filepath.Join(filepath.Dir(cfgPath), "syswatch.log"), 1<<20)
	logger.Printf("syswatch %s starting", version)

	a := app.New(cfgPath, logger)
	a.OnConfig = func(c *config.Config) {
		if err := platform.SetAutostart(c.Autostart, platform.Exe()); err != nil {
			logger.Printf("autostart: %v", err)
		}
	}
	if err := a.Start(); err != nil {
		logger.Printf("start: %v", err)
		os.Exit(1)
	}
	if a.FirstRun() {
		_ = platform.Open(cfgPath) // let the user set output_dir
	}

	quit := func() { a.Stop(); logger.Printf("syswatch stopped") }
	if *headless {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
		<-sig
		quit()
		return
	}
	tray.Run(a, version, quit)
}
