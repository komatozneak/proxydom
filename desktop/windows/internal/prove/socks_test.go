package prove

import "testing"

func TestURLHostPort(t *testing.T) {
	if got := urlHostPort("https://ifconfig.me"); got != "ifconfig.me:443" {
		t.Fatal(got)
	}
	if got := urlHostPort("https://example.com/path"); got != "example.com:443" {
		t.Fatal(got)
	}
}
