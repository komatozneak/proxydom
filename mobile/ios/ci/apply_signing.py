#!/usr/bin/env python3
"""CI-only: set Manual signing + profile names on Runner and VpnTunnelProvider."""

from __future__ import annotations

import os
import pathlib
import re
import sys


def _require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        print(f"missing env {name}", file=sys.stderr)
        sys.exit(1)
    return value


def _quote(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9._-]+", value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _inject(settings_block: str, key: str, value: str) -> str:
    line = f"\t\t\t\t{key} = {value};\n"
    pattern = re.compile(rf"^\t\t\t\t{re.escape(key)} = .*?;\n", re.M)
    if pattern.search(settings_block):
        return pattern.sub(line, settings_block, count=1)
    return settings_block.replace(
        "\t\t\t\tbuildSettings = {\n",
        "\t\t\t\tbuildSettings = {\n" + line,
        1,
    )


def main() -> None:
    team = _require("APPLE_TEAM_ID")
    app_profile = _require("APP_PROFILE_NAME")
    tunnel_profile = _require("TUNNEL_PROFILE_NAME")
    pbx = pathlib.Path(__file__).resolve().parents[1] / "Runner.xcodeproj" / "project.pbxproj"
    text = pbx.read_text(encoding="utf-8")

    def patch_identifier(bundle_id: str, profile: str, src: str) -> str:
        # Target configs include PRODUCT_BUNDLE_IDENTIFIER = bundle_id;
        marker = f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id};"
        out = src
        start = 0
        while True:
            idx = out.find(marker, start)
            if idx < 0:
                break
            block_start = out.rfind("buildSettings = {", 0, idx)
            block_end = out.find("\n\t\t\t};", idx)
            if block_start < 0 or block_end < 0:
                break
            block = out[block_start : block_end + 6]
            patched = _inject(block, "DEVELOPMENT_TEAM", team)
            patched = _inject(patched, "CODE_SIGN_STYLE", "Manual")
            patched = _inject(patched, "PROVISIONING_PROFILE_SPECIFIER", _quote(profile))
            patched = _inject(patched, "CODE_SIGN_IDENTITY", '"Apple Distribution"')
            out = out[:block_start] + patched + out[block_end + 6 :]
            start = block_start + len(patched)
        return out

    text = patch_identifier("online.teremokconnect.app", app_profile, text)
    text = patch_identifier(
        "online.teremokconnect.app.VpnTunnelProvider", tunnel_profile, text
    )
    pbx.write_text(text, encoding="utf-8")
    print(f"patched signing in {pbx}")


if __name__ == "__main__":
    main()
