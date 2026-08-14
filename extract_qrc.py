#!/usr/bin/env python3
import argparse
import os
import re
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape


COMPRESSED = 0x01
DIRECTORY = 0x02


class ExtractError(Exception):
    pass


@dataclass(frozen=True)
class ResourceNode:
    index: int
    name_offset: int
    flags: int
    field1: int
    field2: int
    mtime: int | None

    @property
    def is_dir(self) -> bool:
        return bool(self.flags & DIRECTORY)

    @property
    def is_compressed(self) -> bool:
        return bool(self.flags & COMPRESSED)


def strip_c_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//.*", "", text)


def extract_c_array(text: str, name: str) -> bytes:
    match = re.search(
        rf"static\s+const\s+unsigned\s+char\s+{re.escape(name)}\s*\[\]\s*=\s*\{{(.*?)\n\s*\}};",
        text,
        flags=re.S,
    )
    if not match:
        raise ExtractError(f"array not found: {name}")

    body = strip_c_comments(match.group(1))
    values: list[int] = []
    for token in re.finditer(r"0[xX][0-9a-fA-F]+|\b\d+\b", body):
        value = int(token.group(0), 0)
        if value < 0 or value > 0xFF:
            raise ExtractError(f"{name} contains a non-byte value: {token.group(0)}")
        values.append(value)
    return bytes(values)


def require_range(buf: bytes, offset: int, size: int, what: str) -> None:
    if offset < 0 or size < 0 or offset + size > len(buf):
        raise ExtractError(f"{what} is out of range: offset={offset}, size={size}, len={len(buf)}")


def u16be(buf: bytes, offset: int) -> int:
    require_range(buf, offset, 2, "u16")
    return int.from_bytes(buf[offset : offset + 2], "big")


def u32be(buf: bytes, offset: int) -> int:
    require_range(buf, offset, 4, "u32")
    return int.from_bytes(buf[offset : offset + 4], "big")


def u64be(buf: bytes, offset: int) -> int:
    require_range(buf, offset, 8, "u64")
    return int.from_bytes(buf[offset : offset + 8], "big")


def detect_node_size(tree: bytes) -> int:
    candidates = []
    for size in (22, 14):
        if len(tree) % size != 0 or len(tree) < size:
            continue
        count = len(tree) // size
        flags = u16be(tree, 4)
        child_count = u32be(tree, 6)
        first_child = u32be(tree, 10)
        if flags & DIRECTORY and first_child < count and child_count <= count:
            candidates.append(size)

    if not candidates:
        raise ExtractError(f"cannot detect qt_resource_struct node size, len={len(tree)}")
    return candidates[0]


def parse_nodes(tree: bytes) -> list[ResourceNode]:
    node_size = detect_node_size(tree)
    nodes: list[ResourceNode] = []
    for index in range(len(tree) // node_size):
        offset = index * node_size
        mtime = u64be(tree, offset + 14) if node_size >= 22 else None
        nodes.append(
            ResourceNode(
                index=index,
                name_offset=u32be(tree, offset),
                flags=u16be(tree, offset + 4),
                field1=u32be(tree, offset + 6),
                field2=u32be(tree, offset + 10),
                mtime=mtime,
            )
        )
    return nodes


def read_name(names: bytes, offset: int) -> str:
    length = u16be(names, offset)
    start = offset + 6
    byte_len = length * 2
    require_range(names, start, byte_len, "resource name")
    raw = names[start : start + byte_len]
    return raw.decode("utf-16-be")


def walk_tree(nodes: list[ResourceNode], names: bytes) -> list[tuple[str, ResourceNode]]:
    if not nodes:
        raise ExtractError("empty resource tree")

    files: list[tuple[str, ResourceNode]] = []
    visiting: set[int] = set()

    def walk(index: int, parent: str) -> None:
        if index in visiting:
            raise ExtractError(f"cycle in resource tree at node {index}")
        require_node(index, nodes)

        visiting.add(index)
        node = nodes[index]
        if node.is_dir:
            child_count = node.field1
            first_child = node.field2
            if first_child + child_count > len(nodes):
                raise ExtractError(
                    f"directory node {index} children out of range: "
                    f"first={first_child}, count={child_count}, nodes={len(nodes)}"
                )
            for child_index in range(first_child, first_child + child_count):
                child = nodes[child_index]
                child_name = read_name(names, child.name_offset)
                child_path = f"{parent}/{child_name}" if parent else child_name
                walk(child_index, child_path)
        else:
            if not parent:
                raise ExtractError(f"file node {index} has an empty resource path")
            files.append((parent, node))
        visiting.remove(index)

    walk(0, "")
    return files


def require_node(index: int, nodes: list[ResourceNode]) -> None:
    if index < 0 or index >= len(nodes):
        raise ExtractError(f"node index out of range: {index}")


def qt_uncompress(payload: bytes) -> bytes:
    if len(payload) < 4:
        raise ExtractError("compressed payload is shorter than Qt length header")
    expected_size = u32be(payload, 0)
    try:
        data = zlib.decompress(payload[4:])
    except zlib.error as exc:
        raise ExtractError(str(exc)) from exc
    if expected_size != len(data):
        raise ExtractError(f"unexpected uncompressed size: got={len(data)}, expected={expected_size}")
    return data


def decode_payload(path: str, data: bytes, node: ResourceNode) -> bytes:
    offset = node.field2
    size = u32be(data, offset)
    payload_start = offset + 4
    require_range(data, payload_start, size, f"resource payload for {path}")
    payload = data[payload_start : payload_start + size]

    if not node.is_compressed:
        return payload

    errors: list[str] = []
    candidates: list[tuple[str, bytes]] = []
    if payload:
        candidates.append(("algorithm-prefixed qCompress/zlib", payload[1:]))
    candidates.append(("plain qCompress/zlib", payload))

    for label, candidate in candidates:
        try:
            return qt_uncompress(candidate)
        except ExtractError as exc:
            errors.append(f"{label}: {exc}")

    detail = "; ".join(errors)
    raise ExtractError(f"cannot decompress {path}: {detail}")


def safe_output_path(output_dir: Path, resource_path: str) -> Path:
    if resource_path.startswith("/") or "\\" in resource_path:
        raise ExtractError(f"unsafe resource path: {resource_path}")
    parts = resource_path.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise ExtractError(f"unsafe resource path: {resource_path}")

    output_path = output_dir.joinpath(*parts)
    output_root = output_dir.resolve()
    resolved_parent = output_path.parent.resolve(strict=False)
    if output_root != resolved_parent and output_root not in resolved_parent.parents:
        raise ExtractError(f"resource path escapes output dir: {resource_path}")
    return output_path


def write_qrc(output_dir: Path, files: list[str]) -> None:
    lines = ["<RCC>", '    <qresource prefix="/">']
    for path in files:
        lines.append(f"        <file>{xml_escape(path)}</file>")
    lines.extend(["    </qresource>", "</RCC>", ""])
    (output_dir / "resources.qrc").write_text("\n".join(lines), encoding="utf-8")


def extract(input_file: Path, output_dir: Path, write_manifest: bool) -> int:
    text = input_file.read_text(encoding="utf-8", errors="surrogateescape")
    data = extract_c_array(text, "qt_resource_data")
    names = extract_c_array(text, "qt_resource_name")
    tree = extract_c_array(text, "qt_resource_struct")

    nodes = parse_nodes(tree)
    resources = walk_tree(nodes, names)
    output_dir.mkdir(parents=True, exist_ok=True)

    written: list[str] = []
    seen: set[str] = set()
    for resource_path, node in resources:
        if resource_path in seen:
            raise ExtractError(f"duplicate resource path is not supported: :/{resource_path}")
        seen.add(resource_path)

        payload = decode_payload(resource_path, data, node)
        output_path = safe_output_path(output_dir, resource_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(payload)
        written.append(resource_path)

    if write_manifest:
        write_qrc(output_dir, written)

    return len(written)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract files from a Qt rcc-generated C++ qrc header/source.",
    )
    parser.add_argument("input", help="rcc-generated C++ file, for example qrc_qml.h")
    parser.add_argument("output_dir", help="directory to write extracted resource files")
    parser.add_argument(
        "--no-qrc",
        action="store_true",
        help="do not generate resources.qrc in the output directory",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        count = extract(Path(args.input), Path(args.output_dir), write_manifest=not args.no_qrc)
    except ExtractError as exc:
        print(f"extract_qrc.py: error: {exc}", file=sys.stderr)
        return 1

    manifest = "" if args.no_qrc else " and resources.qrc"
    print(f"extracted {count} files{manifest} to {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
