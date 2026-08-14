#!/usr/bin/env python3
"""Isolate a hysteria gomobile AAR from libXray.

Both gomobile AARs ship `go.Seq` and `libgojni.so`. Android then fails
`:app:checkDebugDuplicateClasses` (and would collide on the .so).

Same-length rewrites so class-file UTF-8 length prefixes stay valid:
  package go  -> hy
  libgojni    -> libhyjni  (loadLibrary \"gojni\" -> \"hyjni\")

ELF JNI exports must NOT be renamed with raw bytes — that leaves DT_GNU_HASH
stale and `hy.Seq.init()` dies with UnsatisfiedLinkError. LIEF rewrites
dynstr + GNU hash together.

Does not merge Go runtimes. Hy2 and Xray still must not run at once.
"""

from __future__ import annotations

import io
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

# Same-length pairs only. Longer names would corrupt class-file u2 lengths.
_CLASS_REPLACEMENTS: tuple[tuple[bytes, bytes], ...] = (
    (b"Java_go_Universe", b"Java_hy_Universe"),
    (b"Java_go_Seq", b"Java_hy_Seq"),
    (b"Java_go_error", b"Java_hy_error"),
    (b"go/Universe", b"hy/Universe"),
    (b"go/Seq", b"hy/Seq"),
    (b"go/error", b"hy/error"),
    (b"Lgo/", b"Lhy/"),
    (b"gojni", b"hyjni"),
)

# FindClass / loadLibrary leftovers in .rodata — not JNI export names.
_SO_RODATA_REPLACEMENTS: tuple[tuple[bytes, bytes], ...] = (
    (b"Java_go_Universe", b"Java_hy_Universe"),
    (b"Java_go_Seq", b"Java_hy_Seq"),
    (b"Java_go_error", b"Java_hy_error"),
    (b"go/Universe", b"hy/Universe"),
    (b"go/Seq", b"hy/Seq"),
    (b"go/error", b"hy/error"),
    (b"Lgo/", b"Lhy/"),
    (b"gojni", b"hyjni"),
)

_JNI_PREFIX_RENAMES: tuple[tuple[str, str], ...] = (
    ("Java_go_Universe", "Java_hy_Universe"),
    ("Java_go_Seq", "Java_hy_Seq"),
    ("Java_go_error", "Java_hy_error"),
)


def _rewrite_bytes(data: bytes, pairs: tuple[tuple[bytes, bytes], ...]) -> bytes:
    for old, new in pairs:
        if len(old) != len(new):
            raise RuntimeError(f"length mismatch {old!r} vs {new!r}")
        data = data.replace(old, new)
    return data


def _rewrite_class_jar(src: bytes) -> bytes:
    src_buf = io.BytesIO(src)
    out_buf = io.BytesIO()
    with zipfile.ZipFile(src_buf, "r") as zin, zipfile.ZipFile(
        out_buf, "w"
    ) as zout:
        for info in zin.infolist():
            raw = zin.read(info.filename)
            name = info.filename
            if name.startswith("go/"):
                name = "hy/" + name[3:]
            if name.endswith(".class") or name.endswith(".java"):
                raw = _rewrite_bytes(raw, _CLASS_REPLACEMENTS)
            out_info = zipfile.ZipInfo(filename=name, date_time=info.date_time)
            out_info.compress_type = info.compress_type
            zout.writestr(out_info, raw)
    return out_buf.getvalue()


def _rename_jni_symbol(name: str, pairs: tuple[tuple[str, str], ...]) -> str:
    for old, new in pairs:
        if name.startswith(old):
            return new + name[len(old) :]
    return name


def _apply_symbol_renames(parsed: object, pairs: tuple[tuple[str, str], ...]) -> int:
    renamed = 0
    for sym in parsed.dynamic_symbols:  # type: ignore[attr-defined]
        old = sym.name
        if not old:
            continue
        new = _rename_jni_symbol(old, pairs)
        if new != old:
            sym.name = new
            renamed += 1
    if hasattr(parsed, "symbols"):
        for sym in parsed.symbols:
            old = getattr(sym, "name", "") or ""
            if not old:
                continue
            new = _rename_jni_symbol(old, pairs)
            if new != old:
                sym.name = new
    return renamed


def _lief_write(parsed: object) -> bytes:
    with tempfile.NamedTemporaryFile(suffix=".so", delete=False) as tmp:
        out_path = Path(tmp.name)
    try:
        parsed.write(str(out_path))  # type: ignore[attr-defined]
        return out_path.read_bytes()
    finally:
        out_path.unlink(missing_ok=True)


def _rewrite_elf(so: bytes) -> bytes:
    """Rename Java_go_* exports via LIEF so GNU hash matches dynstr.

    A previous raw ``bytes.replace`` on this .so left ``Java_hy_*`` in dynstr
    with a GNU hash still keyed on ``Java_go_*``. LIEF only rebuilds the hash
    when a symbol name actually changes, so that broken AAR is first renamed
    hy→go (restore consistent ELF) then go→hy (hash-aware JNI names).
    """
    try:
        import lief
    except ImportError as err:
        raise SystemExit(
            "namespace_aar: pip install lief  (ELF GNU hash rebuild)"
        ) from err

    reverse = tuple((new, old) for old, new in _JNI_PREFIX_RENAMES)
    parsed = lief.parse(so)
    if parsed is None:
        raise RuntimeError("lief.parse failed for libhyjni/libgojni")

    already_hy = any(
        (s.name or "").startswith("Java_hy_Seq") for s in parsed.dynamic_symbols
    )
    if already_hy:
        n_rev = _apply_symbol_renames(parsed, reverse)
        so = _lief_write(parsed)
        parsed = lief.parse(so)
        if parsed is None:
            raise RuntimeError("lief.parse failed after hy→go")
        print(f"  elf: reversed {n_rev} Java_hy_* dynsyms (stale-hash repair)")

    n_fwd = _apply_symbol_renames(parsed, _JNI_PREFIX_RENAMES)
    rebuilt = _lief_write(parsed)
    rebuilt = _rewrite_bytes(rebuilt, _SO_RODATA_REPLACEMENTS)
    print(f"  elf: renamed {n_fwd} Java_go_* symbols, wrote {len(rebuilt)} bytes")
    return rebuilt


def _exported_names(so: bytes) -> set[str]:
    import lief

    parsed = lief.parse(so)
    if parsed is None:
        return set()
    names: set[str] = set()
    for sym in parsed.dynamic_symbols:
        n = sym.name
        if n:
            names.add(n)
    return names


def _gnu_hash(name: str) -> int:
    h = 5381
    for c in name.encode("ascii"):
        h = ((h << 5) + h + c) & 0xFFFFFFFF
    return h


def _gnu_hash_has_symbol(so: bytes, name: str) -> bool:
    """True when DT_GNU_HASH would find [name] (what Android dlsym uses)."""
    import struct

    import lief

    parsed = lief.parse(so)
    if parsed is None:
        return False
    sec = parsed.get_section(".gnu.hash")
    if sec is None:
        return False
    data = bytes(sec.content)
    if len(data) < 16:
        return False
    nbuckets, symoffset, bloom_size, _bloom_shift = struct.unpack_from("<IIII", data)
    off = 16 + bloom_size * 8
    if off + 4 * nbuckets > len(data):
        return False
    buckets = [
        struct.unpack_from("<I", data, off + 4 * i)[0] for i in range(nbuckets)
    ]
    chains_off = off + 4 * nbuckets
    h1 = _gnu_hash(name)
    idx = buckets[h1 % nbuckets]
    if idx < symoffset:
        return False
    dyn = list(parsed.dynamic_symbols)
    i = idx
    while True:
        chain_pos = chains_off + 4 * (i - symoffset)
        if chain_pos + 4 > len(data) or i >= len(dyn):
            return False
        chain = struct.unpack_from("<I", data, chain_pos)[0]
        if (h1 & ~1) == (chain & ~1) and dyn[i].name == name:
            return True
        if chain & 1:
            return False
        i += 1


def namespace_aar(aar_path: Path) -> None:
    src = zipfile.ZipFile(aar_path, "r")
    out_buf = io.BytesIO()
    with src, zipfile.ZipFile(out_buf, "w") as zout:
        for info in src.infolist():
            name = info.filename
            raw = src.read(name)
            if name == "classes.jar":
                raw = _rewrite_class_jar(raw)
            elif name.endswith(".so"):
                print(f"namespace_aar: {name}")
                raw = _rewrite_elf(raw)
                if name.endswith("/libgojni.so"):
                    name = name.replace("/libgojni.so", "/libhyjni.so")
            elif name.endswith(".txt") or name.endswith(".pro"):
                raw = _rewrite_bytes(raw, _CLASS_REPLACEMENTS)
            out_info = zipfile.ZipInfo(filename=name, date_time=info.date_time)
            out_info.compress_type = info.compress_type
            zout.writestr(out_info, raw)
    tmp = aar_path.with_suffix(".aar.tmp")
    tmp.write_bytes(out_buf.getvalue())
    shutil.move(str(tmp), str(aar_path))


def _verify(aar_path: Path) -> None:
    with zipfile.ZipFile(aar_path) as z:
        names = z.namelist()
    if any(n.endswith("/libgojni.so") for n in names):
        raise SystemExit("namespace_aar: libgojni.so still present")
    if not any(n.endswith("/libhyjni.so") for n in names):
        raise SystemExit("namespace_aar: libhyjni.so missing")
    with zipfile.ZipFile(aar_path) as z:
        so = z.read("jni/arm64-v8a/libhyjni.so")
        with zipfile.ZipFile(io.BytesIO(z.read("classes.jar"))) as jar:
            jar_names = jar.namelist()
            seq = jar.read("hy/Seq.class")
    if any(n.startswith("go/") for n in jar_names):
        raise SystemExit("namespace_aar: go/ classes still present")
    if b"go/Seq" in seq or b"gojni" in seq:
        raise SystemExit("namespace_aar: Seq.class still references go/ or gojni")
    if b"hyjni" not in seq:
        raise SystemExit("namespace_aar: Seq.class missing hyjni")
    if b"Java_go_Seq" in so or b"go/Seq" in so:
        raise SystemExit("namespace_aar: libhyjni.so still references go.Seq")
    if b"Java_hy_Seq" not in so:
        raise SystemExit("namespace_aar: libhyjni.so missing Java_hy_Seq")
    exported = _exported_names(so)
    if "Java_hy_Seq_init" not in exported:
        raise SystemExit(
            "namespace_aar: Java_hy_Seq_init not in dynamic symbol table "
            f"(have {[n for n in sorted(exported) if 'Seq' in n][:12]})"
        )
    if any(n.startswith("Java_go_Seq") for n in exported):
        raise SystemExit("namespace_aar: Java_go_Seq still exported")
    if not _gnu_hash_has_symbol(so, "Java_hy_Seq_init"):
        raise SystemExit(
            "namespace_aar: DT_GNU_HASH cannot find Java_hy_Seq_init (dlsym would fail)"
        )
    print(f"namespaced {aar_path} (hy.Seq + libhyjni.so, Java_hy_Seq_init exported)")


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: namespace_aar.py <hysteria-client.aar>", file=sys.stderr)
        raise SystemExit(2)
    aar_path = Path(sys.argv[1]).resolve()
    if not aar_path.is_file():
        raise SystemExit(f"not found: {aar_path}")
    namespace_aar(aar_path)
    _verify(aar_path)


if __name__ == "__main__":
    main()
