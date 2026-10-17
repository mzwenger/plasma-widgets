#!/usr/bin/env python3
"""Lista las particiones del disco al que pertenece ORIGEN, con tamaño y espacio libre.

Uso: disk-info.py ORIGEN NOMBRE
ORIGEN es un punto de montaje o una ruta /dev/...
NOMBRE es el nombre del widget; se usa en la partición que coincide con ORIGEN.
Imprime un JSON por stdout. Los errores van a stderr.
"""

import json
import os
import re
import subprocess
import sys

FS_TYPE = {
    "ntfs": "NTFS",
    "ext4": "ext4",
    "vfat": "FAT32",
    "swap": "swap",
    "exfat": "exFAT",
    "btrfs": "btrfs",
    "xfs": "xfs",
}


def run(args, timeout=8, text=True):
    return subprocess.run(args, capture_output=True, text=text, timeout=timeout)


def resolve_device(source):
    if source.startswith("/dev/"):
        return os.path.realpath(source)
    result = run(["findmnt", "-n", "-o", "SOURCE", "--target", source])
    src = ""
    if result.stdout.strip():
        src = result.stdout.strip().splitlines()[0].split()[0]
    if not src:
        best = ""
        with open("/proc/mounts", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                bits = line.split()
                if len(bits) < 2:
                    continue
                mount = bits[1].replace("\\040", " ")
                if source == mount or source.startswith(mount.rstrip("/") + "/"):
                    if len(mount) > len(best):
                        best = mount
                        src = bits[0]
    if not src:
        raise RuntimeError("no hay dispositivo para " + source)
    if src.startswith("UUID="):
        src = "/dev/disk/by-uuid/" + src.split("=", 1)[1]
    elif src.upper().startswith("PARTUUID="):
        src = "/dev/disk/by-partuuid/" + src.split("=", 1)[1]
    return os.path.realpath(src)


def parent_disk(device):
    result = run(["lsblk", "-no", "PKNAME", device])
    name = result.stdout.strip().splitlines()[0].strip() if result.stdout.strip() else ""
    if not name:
        return device
    return "/dev/" + name


def partitions(disk):
    result = run(
        [
            "lsblk", "-b", "-J", "-o",
            "NAME,PATH,SIZE,FSTYPE,LABEL,PARTTYPENAME,MOUNTPOINTS,PARTUUID,START",
            disk,
        ]
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise RuntimeError(result.stderr.strip() or "lsblk no devolvió datos")
    devices = json.loads(result.stdout).get("blockdevices") or []
    if not devices:
        return []
    nodes = [node for node in (devices[0].get("children") or []) if node.get("path")]
    nodes.sort(key=lambda node: node.get("start") or 0)
    return nodes


def mountpoints(node):
    found = []
    for mount in node.get("mountpoints") or []:
        if mount and mount != "[SWAP]":
            found.append(mount)
    return found


def is_swap(node):
    if (node.get("fstype") or "") == "swap":
        return True
    return "[SWAP]" in (node.get("mountpoints") or [])


def df_size_free(mount):
    result = run(["df", "-B1", "--output=size,avail", "--", mount])
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    if len(lines) < 2:
        return None
    bits = lines[-1].split()
    if len(bits) < 2:
        return None
    try:
        return int(bits[0]), int(bits[1])
    except ValueError:
        return None


def ntfs_size_free(path):
    result = run(["sudo", "-n", "ntfsinfo", "-f", "-m", path], timeout=15)
    cluster = total = free = None
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if line.startswith("Cluster Size:"):
            cluster = int(line.split()[-1])
        elif line.startswith("Volume Size in Clusters:"):
            total = int(line.split()[-1])
        elif line.startswith("Free Clusters:"):
            free = int(line.split()[2])
    if not cluster or total is None or free is None:
        return None
    return cluster * total, cluster * free


def swap_size_free(path):
    real = os.path.realpath(path)
    with open("/proc/swaps", encoding="utf-8", errors="replace") as handle:
        next(handle, None)
        for line in handle:
            bits = line.split()
            if len(bits) < 4:
                continue
            if os.path.realpath(bits[0]) == real:
                # Filename, Type, Size, Used, Priority. Size y Used están en KiB.
                size = int(bits[2]) * 1024
                used = int(bits[3]) * 1024
                return size, max(0, size - used)
    return None


def vfat_free(path, part_size):
    # -n no escribe: solo cuenta clusters. La EFI de Windows no está montada.
    check = run(["sudo", "-n", "fsck.vfat", "-n", path], timeout=20)
    match = re.search(r"(\d+)/(\d+) clusters", check.stdout + "\n" + check.stderr)
    if not match:
        return None
    used = int(match.group(1))
    total = int(match.group(2))
    if total < used:
        return None
    sector = run(["sudo", "-n", "dd", "if=" + path, "bs=512", "count=1"], timeout=5, text=False)
    boot = sector.stdout or b""
    if len(boot) < 14:
        return None
    bytes_per_sector = int.from_bytes(boot[11:13], "little")
    sectors_per_cluster = boot[13]
    if bytes_per_sector not in (512, 1024, 2048, 4096) or not 1 <= sectors_per_cluster <= 128:
        return None
    cluster = bytes_per_sector * sectors_per_cluster
    size = total * cluster
    free = (total - used) * cluster
    if part_size > 0 and size > part_size * 2:
        return None
    return size, free


def title_and_type(node, is_default, widget_name):
    fstype = node.get("fstype") or ""
    parttype = node.get("parttypename") or ""
    label = (node.get("label") or "").strip()
    mounts = mountpoints(node)
    type_label = FS_TYPE.get(fstype, "")
    if is_swap(node):
        return "Intercambio", "swap"
    if label:
        title = label
    elif is_default and widget_name:
        title = widget_name
    elif parttype == "EFI System":
        title = "EFI"
    elif parttype == "Microsoft reserved":
        title = "Reservada"
    elif parttype == "Windows recovery environment":
        title = "Recuperación"
    elif mounts:
        mount = mounts[0]
        title = "Sistema" if mount == "/" else (os.path.basename(mount.rstrip("/")) or mount)
    else:
        title = node.get("name") or "Partición"
    if not type_label:
        if parttype == "Microsoft reserved":
            type_label = "MSR"
        elif parttype == "EFI System":
            type_label = "EFI"
        else:
            type_label = "—"
    return title, type_label


def mounted_usage(node):
    # lsblk pone primero los bind de Docker en /var/lib/docker. Ese directorio
    # no es legible, df falla y la partición quedaba con tamaño pero sin uso.
    # datos-nvme también está en /mnt/datos-nvme: se prueba ese montaje.
    mounts = mountpoints(node)
    mounts.sort(key=lambda mount: (mount.startswith("/var/lib/docker/"), len(mount)))
    for mount in mounts:
        got = df_size_free(mount)
        if got:
            return got
    return None


def space_of(node, part_size):
    path = os.path.realpath(node.get("path"))
    fstype = node.get("fstype") or ""
    if is_swap(node):
        got = swap_size_free(path)
        if got:
            return got
        return part_size, None
    got = mounted_usage(node)
    if got:
        return got
    if mountpoints(node):
        return part_size, None
    if fstype == "ntfs":
        got = ntfs_size_free(path)
        if got:
            return got
        return part_size, None
    if fstype == "vfat":
        got = vfat_free(path, part_size)
        if got:
            return got
        return part_size, None
    return part_size, None


def collect(source, widget_name):
    device = resolve_device(source)
    nodes = partitions(parent_disk(device))
    parts = []
    for node in nodes:
        path = os.path.realpath(node.get("path"))
        part_size = int(node.get("size") or 0)
        try:
            size, free = space_of(node, part_size)
        except Exception as exc:
            print("disk-info: " + str(node.get("name")) + ": " + str(exc), file=sys.stderr)
            size, free = part_size, None
        is_default = path == device
        title, type_label = title_and_type(node, is_default, widget_name)
        parts.append(
            {
                "id": node.get("partuuid") or node.get("name") or path,
                "kname": node.get("name") or os.path.basename(path),
                "name": title,
                "type": type_label,
                "size": int(size or 0),
                "free": None if free is None else int(free),
                "isDefault": is_default,
            }
        )
    return parts


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "/"
    widget_name = sys.argv[2] if len(sys.argv) > 2 else ""
    try:
        parts = collect(source, widget_name)
    except Exception as exc:
        print("disk-info: " + str(exc), file=sys.stderr)
        parts = []
    json.dump({"parts": parts}, sys.stdout, ensure_ascii=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
