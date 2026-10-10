# Security policy

## Reporting a vulnerability

**Do not open a public issue for a security problem.** Use GitHub's private
reporting:

**Security → Report a vulnerability** on
<https://github.com/komatozneak/proxydom/security/advisories/new>

Please include the affected platform and version, what an attacker gains, and
the smallest reproduction you have. A working proof of concept is welcome — we
will not treat a report as hostile for containing one.

We aim to acknowledge a report within three working days. There is no bug
bounty.

## What this project is

Proxy Dom is a **local configuration client**. It runs no service, holds no
accounts, and never sends proxy credentials anywhere. That shapes what counts as
a vulnerability here:

| In scope | Out of scope |
|---|---|
| Credentials from a pasted key or subscription document leaking into logs, crash reports, diagnostics or the UI | The security of the proxy servers a user chooses to connect to |
| A malicious key or document causing code execution, or reading files outside the app sandbox | Whether a third-party server logs traffic |
| The tunnel failing open — traffic leaving outside the tunnel after the app reports it is protected | Traffic analysis of an encrypted tunnel |
| Bypassing the kill switch or the split-tunnel rules | A server operator seeing connection metadata |
| A signed build shipping a dependency that is not under a permissive licence | Denial of service against a server the user configured |
| Credentials surviving in app storage after the user removes the configuration | A rooted or jailbroken device attacking itself |

## Supported versions

Only the latest release on each store receives fixes. Older builds are not
patched.

## Licence boundary is security-relevant

The client is built from permissive licences only (MIT, BSD, ISC, Apache-2.0,
MPL-2.0). A GPL-3.0 or AGPL-3.0 dependency in the shipped binary is a release
blocker, not a style preference: those licences are incompatible with the App
Store terms, and the conflict is about distribution rather than price. A report
that a copyleft dependency has entered the build is welcome and treated as
security-relevant.

See [`mobile/assets/legal/THIRD-PARTY-NOTICES.md`](mobile/assets/legal/THIRD-PARTY-NOTICES.md)
for the inventory of modules compiled into the engine; it is generated from the
dependency graph and ships inside the app.
