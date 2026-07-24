#!/usr/bin/env python3
"""Create a deterministic page-marked UTF-8 text derivative from a PDF."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

from pypdf import PdfReader


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def normalize(text: str) -> str:
    text = text.replace("\x00", " ").replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[\t\f\v ]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    output_path = Path(args.output).resolve()
    if not input_path.is_file() or input_path.suffix.lower() != ".pdf":
        raise SystemExit(f"Input must be an existing PDF: {input_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    reader = PdfReader(str(input_path))
    pages: list[str] = []
    nonempty_pages = 0
    for index, page in enumerate(reader.pages, start=1):
        text = normalize(page.extract_text() or "")
        if text:
            nonempty_pages += 1
        pages.append(f"[[PAGE {index}]]\n{text}")
    output_path.write_text("\n\n".join(pages) + "\n", encoding="utf-8", newline="\n")

    print(
        json.dumps(
            {
                "schemaVersion": "open-education/subject-brain-pdf-derivative/v1",
                "inputSha256": sha256_file(input_path),
                "outputSha256": sha256_file(output_path),
                "pageCount": len(reader.pages),
                "nonemptyPageCount": nonempty_pages,
                "outputBytes": output_path.stat().st_size,
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
