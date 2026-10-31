// Command aarstamp records or checks the source stamp that ties a
// hysteria-client.aar back to the hy2bind source it was built from.
//
//	aarstamp stamp  <package dir> <aar>   record the current hash beside the archive
//	aarstamp verify <package dir> <aar>   non-zero when the archive is missing or stale
//	aarstamp hash   <package dir>         print the hash the archive should carry
//
// build-aar.sh runs `stamp` after binding. build-sideload.ps1 runs `verify`
// before it builds a production APK.
package main

import (
	"fmt"
	"os"

	"proxydom/hy2bind/internal/aarstamp"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: aarstamp [stamp|verify] <package dir> <aar> | hash <package dir>")
		os.Exit(2)
	}
	action, pkgDir := os.Args[1], os.Args[2]

	switch action {
	case "hash":
		hash, err := aarstamp.SourceHash(pkgDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "aarstamp: %v\n", err)
			os.Exit(1)
		}
		fmt.Println(hash)

	case "stamp":
		if len(os.Args) != 4 {
			fmt.Fprintln(os.Stderr, "usage: aarstamp stamp <package dir> <aar>")
			os.Exit(2)
		}
		aar := os.Args[3]
		hash, err := aarstamp.Write(pkgDir, aar)
		if err != nil {
			fmt.Fprintf(os.Stderr, "aarstamp: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("aarstamp: %s <- %s\n", aarstamp.SidecarPath(aar), hash)

	case "verify":
		if len(os.Args) != 4 {
			fmt.Fprintln(os.Stderr, "usage: aarstamp verify <package dir> <aar>")
			os.Exit(2)
		}
		if err := aarstamp.Verify(pkgDir, os.Args[3]); err != nil {
			fmt.Fprintf(os.Stderr, "aarstamp: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("aarstamp: the archive matches the source")

	default:
		fmt.Fprintln(os.Stderr, "usage: aarstamp [stamp|verify] <package dir> <aar> | hash <package dir>")
		os.Exit(2)
	}
}
