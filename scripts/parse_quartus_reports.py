from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


HEADERS = [
    "family",
    "N",
    "implementation",
    "top_module",
    "mode",
    "ALMs",
    "registers",
    "memory_bits",
    "RAM_blocks",
    "DSP_blocks",
    "Fmax",
    "worst_setup_slack",
    "timing_pass_fail",
    "compile_status",
    "report_dir",
]


def read_text(path: Path | None) -> str:
    if path is None or not path.exists():
        return ""
    return path.read_text(errors="ignore")


def first_file(report_dir: Path, pattern: str) -> Path | None:
    files = sorted(report_dir.glob(pattern))
    return files[0] if files else None


def clean_number(value: str) -> str:
    return value.replace(",", "").strip()


def first_match(text: str, patterns: list[str], flags: int = 0) -> str:
    for pattern in patterns:
        match = re.search(pattern, text, flags)
        if match:
            return clean_number(match.group(1))
    return "N/A"


def parse_compile_status(flow_text: str, map_text: str, fit_text: str) -> str:
    combined = "\n".join([flow_text, map_text, fit_text])

    if "was unsuccessful" in combined or re.search(r"\bError \(", combined):
        return "FAIL"

    if "Full Compilation was successful" in combined:
        return "PASS"

    if "Analysis & Synthesis was successful" in combined:
        return "PASS"

    if re.search(r"Flow Status\s*;\s*Successful", combined):
        return "PASS"

    return "N/A"


def parse_timing_status(slack: str) -> str:
    if slack == "N/A":
        return "N/A"

    try:
        return "PASS" if float(slack) >= 0.0 else "FAIL"
    except ValueError:
        return "N/A"


def parse_report_dir(root: Path, report_dir: Path) -> dict[str, str]:
    rel_parts = report_dir.relative_to(root).parts
    if len(rel_parts) >= 2 and rel_parts[0] == "synth":
        family = rel_parts[1]
    else:
        family = "cyclonev" if len(rel_parts) == 1 else (rel_parts[0] if rel_parts else "N/A")
    leaf = rel_parts[-1] if rel_parts else report_dir.name

    n_match = re.search(r"N(\d+)", leaf)
    n_value = n_match.group(1) if n_match else "N/A"
    report_path = str(report_dir).lower()
    if "cyclonev_ai" in report_path:
        implementation = "ai_postprocess"
    elif len(rel_parts) == 1 and re.fullmatch(r"N\d+", leaf):
        implementation = "dsp_pipelined"
    elif "cyclonev_dsp_pipelined" in report_path:
        implementation = "dsp_pipelined"
    elif "cyclonev_pipelined" in report_path:
        implementation = "pipelined"
    else:
        implementation = "baseline"

    map_text = read_text(first_file(report_dir, "*.map.rpt"))
    fit_text = read_text(first_file(report_dir, "*.fit.rpt"))
    sta_text = read_text(first_file(report_dir, "*.sta.rpt"))
    flow_text = read_text(first_file(report_dir, "*.flow.rpt"))

    mode = "synth_only" if "synth_only" in leaf.lower() or not fit_text else "full_compile"

    top_module = first_match(
        map_text,
        [
            r"Top-level Entity Name\s*;\s*([^;]+)\s*;",
            r'Elaborating entity "([^"]+)" for the top level hierarchy',
            r"Changed top-level design entity name to \"([^\"]+)\"",
        ],
    )

    alms = first_match(
        fit_text,
        [
            r"Logic utilization \(in ALMs\)\s*;\s*([\d,]+)\s*/",
            r"Logic utilization \(ALMs needed / total ALMs on device\)\s*;\s*([\d,]+)\s*/",
        ],
    )

    registers = first_match(
        fit_text,
        [
            r"Dedicated logic registers\s*;\s*([\d,]+)\s*/",
            r"Dedicated Logic Registers\s*;\s*([\d,]+)\s*;",
        ],
    )

    memory_bits = first_match(
        fit_text,
        [
            r"Total block memory bits\s*;\s*([\d,]+)\s*/",
            r"Block Memory Bits\s*;\s*([\d,]+)\s*;",
        ],
    )

    ram_blocks = first_match(
        fit_text,
        [
            r"M10K blocks\s*;\s*([\d,]+)\s*/",
            r"M20K blocks\s*;\s*([\d,]+)\s*/",
            r"RAM Blocks\s*;\s*([\d,]+)\s*/",
        ],
    )

    if ram_blocks == "N/A":
        ram_blocks = first_match(map_text, [r"Implemented\s+([\d,]+)\s+RAM segments"])

    dsp_blocks = first_match(
        fit_text,
        [
            r"Total DSP Blocks\s*;\s*([\d,]+)\s*/",
            r"DSP Blocks\s*;\s*([\d,]+)\s*;",
        ],
    )

    if dsp_blocks == "N/A":
        dsp_blocks = first_match(map_text, [r"Implemented\s+([\d,]+)\s+DSP elements"])

    worst_setup_slack = first_match(
        sta_text,
        [
            r"Worst-case setup slack\s*;\s*([-\d.]+)",
            r"Setup\s+slack\s*[:=]\s*([-\d.]+)",
            r"Slack\s*;\s*([-\d.]+)",
        ],
        flags=re.IGNORECASE,
    )

    fmax_values = [
        float(match.group(1))
        for match in re.finditer(
            r";\s*([\d.]+)\s*MHz\s*;\s*[\d.]+\s*MHz\s*;\s*clk\s*;",
            sta_text,
            re.IGNORECASE,
        )
    ]

    if fmax_values:
        fmax = f"{min(fmax_values):g}"
    else:
        fmax = first_match(
            sta_text,
            [
                r"Fmax\s+Summary.*?;\s*clk\s*;\s*([\d.]+)\s*MHz",
                r";\s*clk\s*;\s*([\d.]+)\s*MHz\s*;",
            ],
            flags=re.IGNORECASE | re.DOTALL,
        )

    return {
        "family": family,
        "N": n_value,
        "implementation": implementation,
        "top_module": top_module,
        "mode": mode,
        "ALMs": alms,
        "registers": registers,
        "memory_bits": memory_bits,
        "RAM_blocks": ram_blocks,
        "DSP_blocks": dsp_blocks,
        "Fmax": fmax,
        "worst_setup_slack": worst_setup_slack,
        "timing_pass_fail": parse_timing_status(worst_setup_slack),
        "compile_status": parse_compile_status(flow_text, map_text, fit_text),
        "report_dir": str(report_dir),
    }


def find_report_dirs(root: Path) -> list[Path]:
    if not root.exists():
        return []

    report_dirs: list[Path] = []
    for path in sorted(root.rglob("*")):
        if not path.is_dir():
            continue

        has_reports = any(path.glob("*.map.rpt")) or any(path.glob("*.fit.rpt"))
        if has_reports:
            report_dirs.append(path)

    return report_dirs


def write_csv(rows: list[dict[str, str]], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=HEADERS)
        writer.writeheader()
        writer.writerows(rows)


def write_markdown(rows: list[dict[str, str]], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w") as md_file:
        md_file.write("# Synthesis Summary\n\n")
        md_file.write("| " + " | ".join(HEADERS) + " |\n")
        md_file.write("| " + " | ".join(["---"] * len(HEADERS)) + " |\n")
        for row in rows:
            md_file.write("| " + " | ".join(row[header] for header in HEADERS) + " |\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Summarize Quartus reports.")
    parser.add_argument("--root", default="reports", help="Root synthesis report directory.")
    parser.add_argument("--csv", default="reports/summary.csv", help="Output CSV path.")
    parser.add_argument("--md", default="reports/summary.md", help="Output Markdown path.")
    args = parser.parse_args()

    root = Path(args.root)
    rows = [parse_report_dir(root, report_dir) for report_dir in find_report_dirs(root)]

    write_csv(rows, Path(args.csv))
    write_markdown(rows, Path(args.md))

    print(f"Wrote {len(rows)} report rows to {args.csv} and {args.md}")


if __name__ == "__main__":
    main()
