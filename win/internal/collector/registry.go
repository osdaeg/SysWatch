package collector

// New builds the collector for a module name (nil if unknown).
func New(name string, env *Env) Collector {
	switch name {
	case "cpu":
		return NewCPU(env)
	case "memory":
		return NewMemory(env)
	case "disk":
		return NewDisk(env)
	case "smart":
		return NewSmart(env)
	case "about":
		return NewAbout(env)
	case "network":
		return NewNetwork(env)
	}
	return nil
}
