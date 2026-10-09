package hy2bind

import (
	"strings"
	"testing"
	"time"
)

func TestCongestionConfigFor(t *testing.T) {
	cases := []struct {
		name        string
		cfg         startConfig
		wantType    string
		wantProfile string
		wantWarn    int
	}{
		{
			// Undeclared stays empty so a catalog node keeps today's config.
			name:     "undeclared",
			cfg:      startConfig{},
			wantType: "",
		},
		{
			name:     "explicit bbr",
			cfg:      startConfig{Congestion: "bbr"},
			wantType: "bbr",
		},
		{
			name:     "reno is applied and logged",
			cfg:      startConfig{Congestion: "reno"},
			wantType: "reno",
			wantWarn: 1,
		},
		{
			name:     "case insensitive",
			cfg:      startConfig{Congestion: "BBR"},
			wantType: "bbr",
		},
		{
			name:        "bbr profile aggressive",
			cfg:         startConfig{Congestion: "bbr", BBRProfile: "aggressive"},
			wantType:    "bbr",
			wantProfile: "aggressive",
		},
		{
			// The real foreign link. `brutal` is a mode, not a controller the
			// engine accepts, so it must not be forwarded: an unknown value is
			// a ConfigError that fails the connection.
			name:     "fm brutal mode falls back with a warning",
			cfg:      startConfig{Congestion: "brutal"},
			wantType: "bbr",
			wantWarn: 1,
		},
		{
			name:     "bbr_brutal is the same mode",
			cfg:      startConfig{Congestion: "bbr_brutal"},
			wantType: "bbr",
			wantWarn: 1,
		},
		{
			name:     "bandwidth mode also recognised",
			cfg:      startConfig{Congestion: "bandwidth"},
			wantType: "bbr",
			wantWarn: 1,
		},
		{
			name:     "junk falls back with a warning",
			cfg:      startConfig{Congestion: "cubic"},
			wantType: "bbr",
			wantWarn: 1,
		},
		{
			name:        "junk profile dropped, bbr kept",
			cfg:         startConfig{Congestion: "bbr", BBRProfile: "turbo"},
			wantType:    "bbr",
			wantWarn:    1,
			wantProfile: "",
		},
		{
			// Reno ignores the profile; keeping it would only mislead the log.
			name:        "profile cleared for reno",
			cfg:         startConfig{Congestion: "reno", BBRProfile: "aggressive"},
			wantType:    "reno",
			wantProfile: "",
			wantWarn:    1,
		},
		{
			name:        "profile with no type still applies",
			cfg:         startConfig{BBRProfile: "conservative"},
			wantType:    "bbr",
			wantProfile: "conservative",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gotType, gotProfile, warnings := congestionConfigFor(tc.cfg)
			if gotType != tc.wantType {
				t.Errorf("type = %q, want %q", gotType, tc.wantType)
			}
			if gotProfile != tc.wantProfile {
				t.Errorf("profile = %q, want %q", gotProfile, tc.wantProfile)
			}
			if len(warnings) != tc.wantWarn {
				t.Errorf("warnings = %v, want %d", warnings, tc.wantWarn)
			}
		})
	}
}

func TestCongestionBrutalWarningNamesRequestAndApplied(t *testing.T) {
	_, _, warnings := congestionConfigFor(startConfig{Congestion: "brutal"})
	if len(warnings) != 1 {
		t.Fatalf("warnings = %v, want one", warnings)
	}
	if !strings.Contains(warnings[0], "brutal") || !strings.Contains(warnings[0], "bbr") {
		t.Fatalf("warning %q does not name both the request and bbr", warnings[0])
	}
	if strings.Contains(warnings[0], "rate") || strings.Contains(warnings[0], "mbps") {
		t.Fatalf("warning %q talks about bandwidth", warnings[0])
	}
}

// Whatever a link declares, the value handed to the engine must be one
// NormalizeType / ParseProfile accept, because verifyAndFill makes anything else
// fatal. Empty is the undeclared case and is also accepted.
func TestCongestionConfigForOnlyProducesAcceptedValues(t *testing.T) {
	hostile := []string{
		"brutal", "bandwidth", "cubic", "BBR_BRUTAL", "bbr-brutal", " ", "0",
		"bbr ", " bbr", "reno\n", "Brutal", "none", "null",
	}
	for _, value := range hostile {
		gotType, gotProfile, _ := congestionConfigFor(startConfig{
			Congestion: value,
			BBRProfile: value,
		})
		if gotType != "" {
			if _, ok := congestionTypes[gotType]; !ok {
				t.Errorf("congestion %q produced type %q, which core/v2 rejects", value, gotType)
			}
		}
		if gotProfile != "" {
			if _, ok := bbrProfiles[gotProfile]; !ok {
				t.Errorf("congestion %q produced profile %q, which core/v2 rejects", value, gotProfile)
			}
		}
	}
}

func TestQUICConfigFor(t *testing.T) {
	cases := []struct {
		name      string
		cfg       startConfig
		wantIdle  time.Duration
		wantAlive time.Duration
		wantWarn  int
	}{
		{
			name:      "foreign link timers",
			cfg:       startConfig{MaxIdleTimeout: "20", KeepAlivePeriod: "10"},
			wantIdle:  20 * time.Second,
			wantAlive: 10 * time.Second,
		},
		{
			name: "undeclared stays zero so the engine fills defaults",
			cfg:  startConfig{},
		},
		{
			name:     "below minimum is clamped",
			cfg:      startConfig{MaxIdleTimeout: "1"},
			wantIdle: 4 * time.Second,
			wantWarn: 1,
		},
		{
			name:      "keepalive below minimum is clamped",
			cfg:       startConfig{KeepAlivePeriod: "1"},
			wantAlive: 2 * time.Second,
			wantWarn:  1,
		},
		{
			name:     "above maximum is clamped",
			cfg:      startConfig{MaxIdleTimeout: "200"},
			wantIdle: 120 * time.Second,
			wantWarn: 1,
		},
		{
			name:      "keepalive above maximum is clamped",
			cfg:       startConfig{KeepAlivePeriod: "90"},
			wantAlive: 60 * time.Second,
			wantWarn:  1,
		},
		{
			name:     "exact boundaries pass through unclamped",
			cfg:      startConfig{MaxIdleTimeout: "4", KeepAlivePeriod: "60"},
			wantIdle: 4 * time.Second, wantAlive: 60 * time.Second,
		},
		{
			name: "zero and negative mean unset",
			cfg:  startConfig{MaxIdleTimeout: "0", KeepAlivePeriod: "-5"},
		},
		{
			name:     "unreadable is dropped with a warning",
			cfg:      startConfig{MaxIdleTimeout: "soon"},
			wantWarn: 1,
		},
		{
			name:     "fractional seconds are kept",
			cfg:      startConfig{MaxIdleTimeout: "7.5"},
			wantIdle: 7500 * time.Millisecond,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gotIdle, gotAlive, warnings := quicConfigFor(tc.cfg)
			if gotIdle != tc.wantIdle {
				t.Errorf("maxIdleTimeout = %s, want %s", gotIdle, tc.wantIdle)
			}
			if gotAlive != tc.wantAlive {
				t.Errorf("keepAlivePeriod = %s, want %s", gotAlive, tc.wantAlive)
			}
			if len(warnings) != tc.wantWarn {
				t.Errorf("warnings = %v, want %d", warnings, tc.wantWarn)
			}
		})
	}
}

func TestQUICConfigForClampWarningNamesTheFloor(t *testing.T) {
	_, _, warnings := quicConfigFor(startConfig{MaxIdleTimeout: "1"})
	if len(warnings) != 1 || !strings.Contains(warnings[0], "4s") {
		t.Fatalf("warnings = %v, want a clamp to 4s", warnings)
	}
}

// Every timer handed to the engine must be inside the range verifyAndFill
// enforces, or it fails the connection instead of tuning it.
func TestQUICConfigForNeverProducesOutOfRangeValues(t *testing.T) {
	hostile := []string{
		"0", "1", "3", "3.9", "4", "60", "120", "121", "200", "99999", "-1", "-999",
		"soon", "", " ", "1e9", "NaN", "Inf",
	}
	for _, value := range hostile {
		idle, alive, _ := quicConfigFor(startConfig{
			MaxIdleTimeout:  value,
			KeepAlivePeriod: value,
		})
		if idle != 0 && (idle < minMaxIdleTimeout || idle > maxMaxIdleTimeout) {
			t.Errorf("maxIdleTimeout %q produced %s, outside [%s, %s]",
				value, idle, minMaxIdleTimeout, maxMaxIdleTimeout)
		}
		if alive != 0 && (alive < minKeepAlivePeriod || alive > maxKeepAlivePeriod) {
			t.Errorf("keepAlivePeriod %q produced %s, outside [%s, %s]",
				value, alive, minKeepAlivePeriod, maxKeepAlivePeriod)
		}
	}
}

func TestFormatHy2ConfigLogOmitsValues(t *testing.T) {
	line := formatHy2ConfigLog(
		"bbr", "", 20*time.Second, 10*time.Second,
		"quicParams.brutalUp,quicParams.brutalDown,quicParams.congestion,quicParams.maxIdleTimeout,quicParams.keepAlivePeriod",
	)
	want := `hy2bind config congestion=bbr bbr_profile="" idle=20s keepalive=10s declared=quicParams.brutalUp,quicParams.brutalDown,quicParams.congestion,quicParams.maxIdleTimeout,quicParams.keepAlivePeriod`
	if line != want {
		t.Fatalf("log = %q, want %q", line, want)
	}
	for _, leaked := range []string{"2000", "mbps", "auth", "hy2://"} {
		if strings.Contains(line, leaked) {
			t.Fatalf("log line contains %q: %s", leaked, line)
		}
	}
}

func TestFormatHy2ConfigLogEmptyDeclaration(t *testing.T) {
	line := formatHy2ConfigLog("", "", 0, 0, "")
	want := `hy2bind config congestion= bbr_profile="" idle=0s keepalive=0s declared=`
	if line != want {
		t.Fatalf("log = %q, want %q", line, want)
	}
}

// The wiring: buildClientConfig must carry the controller and the timers,
// and must not grow a bandwidth block from fm.
func TestBuildClientConfigCarriesCongestionAndTimers(t *testing.T) {
	cfg, err := buildClientConfig(startConfig{
		Server:          "203.0.113.10:443",
		Auth:            "user:pass",
		SNI:             "crt.example.com",
		Congestion:      "brutal",
		BBRProfile:      "aggressive",
		MaxIdleTimeout:  "20",
		KeepAlivePeriod: "10",
		Declared:        "quicParams.congestion,quicParams.maxIdleTimeout",
	})
	if err != nil {
		t.Fatalf("buildClientConfig: %v", err)
	}
	if cfg.CongestionConfig.Type != "bbr" {
		t.Errorf("CongestionConfig.Type = %q, want bbr", cfg.CongestionConfig.Type)
	}
	if cfg.CongestionConfig.BBRProfile != "aggressive" {
		t.Errorf("BBRProfile = %q, want aggressive", cfg.CongestionConfig.BBRProfile)
	}
	if cfg.QUICConfig.MaxIdleTimeout != 20*time.Second {
		t.Errorf("MaxIdleTimeout = %s, want 20s", cfg.QUICConfig.MaxIdleTimeout)
	}
	if cfg.QUICConfig.KeepAlivePeriod != 10*time.Second {
		t.Errorf("KeepAlivePeriod = %s, want 10s", cfg.QUICConfig.KeepAlivePeriod)
	}
	if cfg.BandwidthConfig.MaxTx != 0 || cfg.BandwidthConfig.MaxRx != 0 {
		t.Errorf("bandwidth = (%d, %d), want zero", cfg.BandwidthConfig.MaxTx, cfg.BandwidthConfig.MaxRx)
	}
}

func TestBuildClientConfigClampsIdleBelowTheFloor(t *testing.T) {
	cfg, err := buildClientConfig(startConfig{
		Server:         "203.0.113.10:443",
		Auth:           "user:pass",
		MaxIdleTimeout: "1",
	})
	if err != nil {
		t.Fatalf("buildClientConfig: %v", err)
	}
	if cfg.QUICConfig.MaxIdleTimeout != 4*time.Second {
		t.Errorf("MaxIdleTimeout = %s, want 4s", cfg.QUICConfig.MaxIdleTimeout)
	}
}

func TestBuildClientConfigWithoutCongestionUsesDefaults(t *testing.T) {
	cfg, err := buildClientConfig(startConfig{
		Server: "203.0.113.10:443",
		Auth:   "user:pass",
		SNI:    "crt.example.com",
	})
	if err != nil {
		t.Fatalf("buildClientConfig: %v", err)
	}
	if cfg.CongestionConfig.Type != "" {
		t.Errorf("CongestionConfig.Type = %q, want empty", cfg.CongestionConfig.Type)
	}
	if cfg.QUICConfig.MaxIdleTimeout != 0 || cfg.QUICConfig.KeepAlivePeriod != 0 {
		t.Errorf("timers = (%s, %s), want zero so the engine fills its defaults",
			cfg.QUICConfig.MaxIdleTimeout, cfg.QUICConfig.KeepAlivePeriod)
	}
	if cfg.BandwidthConfig.MaxTx != 0 || cfg.BandwidthConfig.MaxRx != 0 {
		t.Errorf("bandwidth = (%d, %d), want zero", cfg.BandwidthConfig.MaxTx, cfg.BandwidthConfig.MaxRx)
	}
}
