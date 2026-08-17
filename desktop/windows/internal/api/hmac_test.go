package api

import "testing"

func TestSignPayloadEmptyBodyKnownVector(t *testing.T) {
	// sha256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
	got := SignPayload(
		"secret",
		"1700000000",
		"abcd",
		"get",
		"/v2/app/connect/get/v3",
		nil,
	)
	want := SignPayload(
		"secret",
		"1700000000",
		"abcd",
		"GET",
		"/v2/app/connect/get/v3",
		[]byte{},
	)
	if got != want {
		t.Fatalf("method case must be normalized: %s vs %s", got, want)
	}
	const wantHex = "c04b3aa34e279b7e8b7900f186f9ff88c3bd7ebab48541db2b6d42c8e0a012f1"
	if got != wantHex {
		t.Fatalf("hmac vector: got %s want %s", got, wantHex)
	}
	other := SignPayload("secret", "1700000000", "abcd", "GET", "/v2/app/connect/get/v3", []byte("x"))
	if other == got {
		t.Fatal("body must be covered by the signature")
	}
}

func TestSignHeadersRequiresSecret(t *testing.T) {
	_, err := SignHeaders("", "GET", "/v2/app/me", nil)
	if err == nil {
		t.Fatal("expected error")
	}
}
