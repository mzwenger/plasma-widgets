#!/usr/bin/env python3
"""Quién movió bytes en un disco desde la muestra anterior.

Uso: disk-top.py DEVICE
DEVICE es un nombre del kernel (nvme0n1p2), una ruta /dev o un punto de montaje.

El kernel no anota bytes por proceso y por disco. /proc/<pid>/io mezcla todos
los discos y no se puede leer en los procesos de Docker. La contabilidad que sí
sirve es la del grupo de procesos (cgroup), en io.stat, y está en el disco
entero: una partición se resuelve a su disco. La sesión del usuario es un solo
grupo; cada contenedor es el suyo.

Imprime un JSON. La primera vez, o si la muestra anterior tiene más de 5 s,
mide un segundo y responde con esa ventana. Errores a stderr.
"""

import json
import os
import pathlib
import subprocess
import sys
import time

MIN_BYTES = 64 * 1024
MAX_GAP = 5.0
FRESH_WAIT = 1.0
CACHE = pathlib.Path.home() / ".cache" / "plasma-diskmonitor"

# Procesos que arrancan el contenedor y no dicen qué está corriendo.
BORING_COMM = {
    "docker-init",
    "tini",
    "dumb-init",
    "catatonit",
    "pause",
    "systemd",
}


def emit(payload):
    json.dump(payload, sys.stdout, ensure_ascii=True)
    sys.stdout.write("\n")


def uptime():
    with open("/proc/uptime", encoding="utf-8") as handle:
        return float(handle.read().split()[0])


def kernel_name(spec):
    spec = (spec or "/").strip()
    block = pathlib.Path("/sys/class/block")
    if "/" not in spec and (block / spec).exists():
        return spec
    if spec.startswith("/dev/"):
        return os.path.basename(os.path.realpath(spec))
    result = subprocess.run(
        ["findmnt", "-n", "-o", "SOURCE", "--target", spec],
        capture_output=True,
        text=True,
        timeout=3,
    )
    src = ""
    if result.stdout.strip():
        src = result.stdout.strip().splitlines()[0].split()[0]
    if not src:
        raise RuntimeError("no hay dispositivo para " + spec)
    if src.startswith("UUID="):
        src = "/dev/disk/by-uuid/" + src.split("=", 1)[1]
    elif src.upper().startswith("PARTUUID="):
        src = "/dev/disk/by-partuuid/" + src.split("=", 1)[1]
    return os.path.basename(os.path.realpath(src))


def whole_disk(kname):
    """La contabilidad io.stat cae en el disco, no en la partición."""
    base = pathlib.Path("/sys/class/block") / kname
    if (base / "partition").exists():
        parent = base.resolve().parent
        if (parent / "dev").exists():
            return parent.name
    return kname


def devnum(kname):
    return (pathlib.Path("/sys/class/block") / kname / "dev").read_text().strip()


def disk_sectors(kname):
    with open("/proc/diskstats", encoding="utf-8") as handle:
        for line in handle:
            bits = line.split()
            if len(bits) > 9 and bits[2] == kname:
                return int(bits[5]) + int(bits[9])
    return None


def bytes_on(text, dev):
    total = 0
    for line in text.splitlines():
        bits = line.split()
        if not bits or bits[0] != dev:
            continue
        for item in bits[1:]:
            if item.startswith("rbytes=") or item.startswith("wbytes="):
                total += int(item.split("=", 1)[1])
    return total


def group_bytes(dev):
    """Solo hojas: el grupo padre ya incluye a los hijos y se contarían dos veces."""
    root = pathlib.Path("/sys/fs/cgroup")
    found = {}
    for stat in root.rglob("io.stat"):
        folder = stat.parent
        try:
            children = [child for child in folder.iterdir() if child.is_dir()]
        except OSError:
            continue
        if any((child / "io.stat").exists() for child in children):
            continue
        try:
            total = bytes_on(stat.read_text(), dev)
        except OSError:
            continue
        if total:
            found[str(folder.relative_to(root))] = total
    return found


def sample(disk, dev):
    return uptime(), disk_sectors(disk), group_bytes(dev)


def state_path(dev):
    return CACHE / ("top-" + dev.replace(":", "-") + ".json")


def load_state(path):
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or not isinstance(data.get("groups"), dict):
        return None
    if "t" not in data or "sectors" not in data:
        return None
    return data


def save_state(path, when, sectors, groups):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps({"t": when, "sectors": sectors, "groups": groups}))
    tmp.replace(path)


def boring(comm):
    return comm in BORING_COMM or comm.startswith("s6-")


def leader_comm(rel):
    procs = pathlib.Path("/sys/fs/cgroup") / rel / "cgroup.procs"
    try:
        pids = procs.read_text().split()
    except OSError:
        return ""
    fallback = ""
    for pid in pids[:16]:
        try:
            comm = pathlib.Path("/proc/" + pid + "/comm").read_text().strip()
        except OSError:
            continue
        if not comm:
            continue
        if not fallback:
            fallback = comm
        if not boring(comm):
            return comm
    return "" if boring(fallback) else fallback


def unit_path(name):
    out = []
    index = 0
    while index < len(name):
        if name[index] == "\\" and index + 3 < len(name) and name[index + 1] == "x":
            try:
                out.append(chr(int(name[index + 2:index + 4], 16)))
            except ValueError:
                out.append(name[index])
                index += 1
                continue
            index += 4
        elif name[index] == "-":
            out.append("/")
            index += 1
        else:
            out.append(name[index])
            index += 1
    text = "".join(out)
    if not text.startswith("/"):
        text = "/" + text
    return text


def docker_names():
    path = CACHE / "docker-names.json"
    cached = {}
    fetched = 0
    try:
        stored = json.loads(path.read_text())
        cached = stored.get("names") or {}
        fetched = float(stored.get("t") or 0)
    except (OSError, ValueError):
        cached = {}
    if cached and time.time() - fetched < 60:
        return cached
    try:
        result = subprocess.run(
            ["docker", "ps", "-a", "--no-trunc", "--format", "{{.ID}} {{.Names}}"],
            capture_output=True,
            text=True,
            timeout=1.5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return cached
    if result.returncode != 0:
        return cached
    names = {}
    for line in result.stdout.splitlines():
        bits = line.split(None, 1)
        if len(bits) == 2 and bits[1]:
            names[bits[0]] = bits[1].lstrip("/")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps({"t": time.time(), "names": names}))
        tmp.replace(path)
    except OSError:
        pass
    return names or cached


def label(rel, names):
    base = rel.rsplit("/", 1)[-1]
    if base == "user.slice":
        return "Sesión de usuario"
    if base.startswith("docker-") and base.endswith(".scope"):
        cid = base[len("docker-"):-len(".scope")]
        if cid in names:
            return names[cid]
        comm = leader_comm(rel)
        return comm or ("contenedor " + cid[:12])
    if base.endswith(".service"):
        return base[:-len(".service")]
    if base.endswith(".mount"):
        return unit_path(base[:-len(".mount")])
    if base.endswith(".scope"):
        return leader_comm(rel) or base[:-len(".scope")]
    return leader_comm(rel) or base


def build_rows(prev, when, sectors, groups):
    dt = when - float(prev["t"])
    if dt <= 0:
        return [], True
    disk_delta = (sectors - int(prev["sectors"])) * 512
    if disk_delta < 0:
        disk_delta = 0
    prev_groups = prev["groups"]
    deltas = []
    for key, total in groups.items():
        if key not in prev_groups:
            continue
        delta = int(total) - int(prev_groups[key])
        if delta > 0:
            deltas.append((delta, key))
    deltas.sort(reverse=True)
    accounted = sum(delta for delta, _key in deltas)
    denom = disk_delta if disk_delta > 0 else accounted
    if denom < MIN_BYTES:
        return [], True
    chosen = []
    for delta, key in deltas:
        pct = min(100.0, 100.0 * delta / denom)
        if pct < 1:
            break
        chosen.append((delta, key, pct))
        if len(chosen) == 5:
            break
    if not chosen and deltas:
        delta, key = deltas[0]
        chosen.append((delta, key, min(100.0, 100.0 * delta / denom)))
    if not chosen:
        return [], False
    needs_docker = False
    for _delta, key, _pct in chosen:
        base = key.rsplit("/", 1)[-1]
        if base.startswith("docker-") and base.endswith(".scope"):
            needs_docker = True
            break
    names = docker_names() if needs_docker else {}
    rows = []
    for delta, key, pct in chosen:
        rows.append({
            "name": label(key, names),
            "pct": round(pct, 1),
            "rate": delta / dt,
        })
    return rows, False


def answer(prev, when, sectors, groups, disk):
    rows, idle = build_rows(prev, when, sectors, groups)
    return {"ready": True, "idle": idle, "disk": disk, "rows": rows}


def main():
    spec = sys.argv[1] if len(sys.argv) > 1 else "/"
    kname = kernel_name(spec)
    disk = whole_disk(kname)
    dev = devnum(disk)
    path = state_path(dev)
    when, sectors, groups = sample(disk, dev)
    if sectors is None:
        raise RuntimeError("no está en diskstats: " + disk)
    prev = load_state(path)
    gap = None if prev is None else when - float(prev["t"])
    if prev is not None and gap is not None and gap < 0.4:
        emit({"ready": False, "idle": False, "disk": disk, "rows": []})
        return
    if prev is not None and gap is not None and gap <= MAX_GAP:
        save_state(path, when, sectors, groups)
        emit(answer(prev, when, sectors, groups, disk))
        return
    # Sin base reciente: medir una ventana corta y responder en esta llamada.
    save_state(path, when, sectors, groups)
    time.sleep(FRESH_WAIT)
    when2, sectors2, groups2 = sample(disk, dev)
    if sectors2 is None:
        raise RuntimeError("no está en diskstats: " + disk)
    save_state(path, when2, sectors2, groups2)
    emit(answer({"t": when, "sectors": sectors, "groups": groups}, when2, sectors2, groups2, disk))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("disk-top: " + str(exc), file=sys.stderr)
        emit({"ready": False, "idle": False, "rows": []})
        sys.exit(0)
