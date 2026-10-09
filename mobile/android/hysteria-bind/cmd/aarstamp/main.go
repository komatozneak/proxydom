// Command aarstamp writes or checks the source stamp that ties the committed
// hysteria-client.aar back to the hy2bind source it was built from.
//
//	aarstamp write <package dir>   rewrite aar_stamp.go with the current hash
//	aarstamp check <package dir>   non-zero when the stamp is stale
//
// build-aar.sh runs `write` before every bind.
package main

import (
	"fmt"
	"os"

	"github.com/komatozneak/proxydom/hy2bind/internal/aarstamp"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: aarstamp [write|check] <package dir>")
		os.Exit(2)
	}
	action, pkgDir := os.Args[1], os.Args[2]
	switch action {
	case "write":
		hash, err := aarstamp.Write(pkgDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "aarstamp: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("aarstamp: wrote %s = %s\n", aarstamp.StampFile, hash)
	case "check":
		want, err := aarstamp.SourceHash(pkgDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "aarstamp: %v\n", err)
			os.Exit(1)
		}
		have, err := aarstamp.CurrentStamp(pkgDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "aarstamp: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("aarstamp: source=%s stamp=%s\n", want, have)
		if want != have {
			fmt.Fprintln(os.Stderr, "aarstamp: the stamp is stale; rebuild the archive with build-aar.sh")
			os.Exit(1)
		}
	default:
		fmt.Fprintln(os.Stderr, "usage: aarstamp [write|check] <package dir>")
		os.Exit(2)
	}
}
