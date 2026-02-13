#!/usr/bin/env python3
"""
PlantGenotationFlow — Indexed Pipeline Report Generator
========================================================
Generates a single-page HTML report with sidebar navigation and multiple
sections covering the entire pipeline: QC, Assembly, Decontamination,
Repeats, and Annotation.

Can be called via Snakemake `script:` directive or from the command line.
"""

import argparse
import base64
import io
import os
import re
import sys
from datetime import datetime

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

def safe_read(path):
    """Read file contents or return None on error."""
    try:
        with open(path, "r") as fh:
            return fh.read()
    except Exception:
        return None


def parse_nanoplot_stats(stats_file):
    """Parse NanoPlot NanoStats.txt into a dict."""
    data = {}
    text = safe_read(stats_file)
    if not text:
        return data
    for line in text.strip().splitlines():
        parts = line.split(":")
        if len(parts) == 2:
            key = parts[0].strip()
            val = parts[1].strip()
            data[key] = val
    return data


def parse_quast_tsv(tsv_file):
    """Parse QUAST report.tsv into {metric: {assembly_label: value}}."""
    data = {}
    text = safe_read(tsv_file)
    if not text:
        return data
    lines = text.strip().splitlines()
    if not lines:
        return data
    headers = lines[0].split("\t")
    for line in lines[1:]:
        cols = line.split("\t")
        metric = cols[0]
        data[metric] = {}
        for i, col in enumerate(cols[1:], 1):
            if i < len(headers):
                data[metric][headers[i]] = col
    return data


def parse_busco_summary(summary_file):
    """Parse BUSCO short_summary.txt → dict with C, S, D, F, M counts."""
    result = {"C": "N/A", "S": "N/A", "D": "N/A", "F": "N/A", "M": "N/A", "Total": "N/A"}
    text = safe_read(summary_file)
    if not text:
        return result
    for line in text.splitlines():
        line = line.strip()
        if "Complete BUSCOs (C)" in line:
            result["C"] = line.split("\t")[0].strip()
        elif "Complete and single-copy BUSCOs (S)" in line:
            result["S"] = line.split("\t")[0].strip()
        elif "Complete and duplicated BUSCOs (D)" in line:
            result["D"] = line.split("\t")[0].strip()
        elif "Fragmented BUSCOs (F)" in line:
            result["F"] = line.split("\t")[0].strip()
        elif "Missing BUSCOs (M)" in line:
            result["M"] = line.split("\t")[0].strip()
        elif "Total BUSCO groups searched" in line:
            result["Total"] = line.split("\t")[0].strip()
    return result


def parse_edta_summary(sum_file):
    """Parse EDTA TEanno.sum for repeat composition."""
    rows = []
    text = safe_read(sum_file)
    if not text:
        return rows
    capture = False
    for line in text.splitlines():
        if "repeat_type" in line.lower() or "Type" in line:
            capture = True
            continue
        if capture and line.strip():
            cols = line.strip().split()
            if len(cols) >= 3:
                rows.append({"type": cols[0], "count": cols[1], "bp": cols[2],
                             "pct": cols[3] if len(cols) > 3 else ""})
    return rows


def parse_gff_stats(gff_file):
    """Count genes & mRNAs in a GFF3 file."""
    genes, mrnas = 0, 0
    text = safe_read(gff_file)
    if not text:
        return {"genes": 0, "mrnas": 0}
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) < 9:
            continue
        if cols[2] == "gene":
            genes += 1
        elif cols[2] in ("mRNA", "transcript"):
            mrnas += 1
    return {"genes": genes, "mrnas": mrnas}


def parse_rejected_ids(rejected_file):
    """Count rejected contigs."""
    text = safe_read(rejected_file)
    if not text:
        return 0
    return len([l for l in text.strip().splitlines() if l.strip() and not l.startswith("#")])


def parse_annotation_stats_txt(stats_file):
    """Read the plain-text stats.txt produced by annotation_stats rule."""
    text = safe_read(stats_file)
    return text if text else "No stats available."


# ---------------------------------------------------------------------------
# HTML Building
# ---------------------------------------------------------------------------

CSS = """
:root {
    --bg: #f5f7fa;
    --sidebar-bg: #1e293b;
    --sidebar-text: #cbd5e1;
    --sidebar-active: #38bdf8;
    --card-bg: #ffffff;
    --border: #e2e8f0;
    --accent: #0ea5e9;
    --text: #1e293b;
    --text-muted: #64748b;
    --success: #22c55e;
    --warning: #f59e0b;
    --danger: #ef4444;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html { scroll-behavior: smooth; }
body {
    font-family: 'Inter', 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: var(--bg);
    color: var(--text);
    display: flex;
    min-height: 100vh;
}
/* Sidebar */
.sidebar {
    width: 260px;
    background: var(--sidebar-bg);
    color: var(--sidebar-text);
    position: fixed;
    top: 0; left: 0; bottom: 0;
    overflow-y: auto;
    padding: 24px 0;
    z-index: 100;
}
.sidebar h2 {
    font-size: 16px;
    padding: 0 20px 16px;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    margin-bottom: 8px;
    color: #fff;
    letter-spacing: 0.5px;
}
.sidebar a {
    display: block;
    padding: 10px 20px 10px 28px;
    color: var(--sidebar-text);
    text-decoration: none;
    font-size: 14px;
    border-left: 3px solid transparent;
    transition: all 0.15s;
}
.sidebar a:hover,
.sidebar a.active {
    background: rgba(255,255,255,0.06);
    color: var(--sidebar-active);
    border-left-color: var(--sidebar-active);
}
.sidebar .nav-section {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 1px;
    color: #475569;
    padding: 16px 20px 6px;
}
/* Main Content */
.main {
    margin-left: 260px;
    padding: 32px 40px;
    flex: 1;
    max-width: 1100px;
}
h1 {
    font-size: 28px;
    margin-bottom: 6px;
}
.subtitle {
    color: var(--text-muted);
    margin-bottom: 32px;
    font-size: 14px;
}
section {
    margin-bottom: 48px;
}
section h2 {
    font-size: 22px;
    margin-bottom: 4px;
    padding-bottom: 8px;
    border-bottom: 2px solid var(--accent);
    display: inline-block;
}
section h3 {
    font-size: 17px;
    margin: 20px 0 10px;
    color: var(--text-muted);
}
.card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 20px 24px;
    margin: 14px 0;
    box-shadow: 0 1px 3px rgba(0,0,0,0.04);
}
table {
    width: 100%;
    border-collapse: collapse;
    font-size: 14px;
    margin: 10px 0;
}
th, td {
    padding: 10px 14px;
    text-align: left;
    border-bottom: 1px solid var(--border);
}
th {
    background: #f1f5f9;
    font-weight: 600;
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.3px;
    color: var(--text-muted);
}
tr:hover td { background: #f8fafc; }
.badge {
    display: inline-block;
    padding: 2px 10px;
    border-radius: 12px;
    font-size: 12px;
    font-weight: 600;
}
.badge-success { background: #dcfce7; color: #166534; }
.badge-warning { background: #fef9c3; color: #854d0e; }
.badge-danger  { background: #fee2e2; color: #991b1b; }
.badge-info    { background: #dbeafe; color: #1e40af; }
pre {
    background: #1e293b;
    color: #e2e8f0;
    padding: 16px;
    border-radius: 8px;
    font-size: 13px;
    overflow-x: auto;
    white-space: pre-wrap;
    word-wrap: break-word;
}
.metric-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 14px;
    margin: 14px 0;
}
.metric-box {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 16px;
    text-align: center;
}
.metric-box .value {
    font-size: 28px;
    font-weight: 700;
    color: var(--accent);
}
.metric-box .label {
    font-size: 12px;
    color: var(--text-muted);
    margin-top: 4px;
}
.sample-tag {
    display: inline-block;
    background: var(--accent);
    color: #fff;
    padding: 3px 12px;
    border-radius: 14px;
    font-size: 13px;
    font-weight: 600;
    margin-right: 6px;
}
footer {
    text-align: center;
    color: var(--text-muted);
    font-size: 12px;
    padding: 24px 0;
    border-top: 1px solid var(--border);
    margin-top: 40px;
}
"""


def build_sidebar(samples):
    """Generate sidebar navigation HTML."""
    links = [
        ("overview", "Overview"),
        ("qc", "Quality Control"),
        ("assembly", "Assembly & Polishing"),
        ("decontamination", "Decontamination"),
        ("repeats", "Repeat Masking"),
        ("annotation", "Annotation"),
        ("summary", "Pipeline Summary"),
    ]
    nav = '<div class="sidebar">\n'
    nav += '  <h2>🌿 PlantGenotationFlow</h2>\n'
    nav += '  <div class="nav-section">Navigation</div>\n'
    for href, label in links:
        nav += f'  <a href="#{href}">{label}</a>\n'
    nav += '  <div class="nav-section">Samples</div>\n'
    for s in samples:
        nav += f'  <a href="#sample-{s}">{s}</a>\n'
    nav += '</div>\n'
    return nav


def section_overview(samples):
    """Section 0: Overview."""
    html = '<section id="overview">\n'
    html += '  <h2>Overview</h2>\n'
    html += '  <div class="card">\n'
    html += '    <p>This report summarises the <strong>PlantGenotationFlow</strong> pipeline results.</p>\n'
    html += f'    <p><strong>Samples processed:</strong> {len(samples)} &mdash; '
    html += " ".join(f'<span class="sample-tag">{s}</span>' for s in samples)
    html += '</p>\n'
    html += f'    <p><strong>Report generated:</strong> {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>\n'
    html += '  </div>\n'

    # Pipeline Flow
    html += '  <div class="card">\n'
    html += '    <h3>Pipeline Steps</h3>\n'
    steps = [
        ("1", "Raw Read QC", "NanoPlot"),
        ("2", "Assembly", "Flye / Hifiasm + Medaka polishing"),
        ("3", "Decontamination", "FCS-Adaptor + Tiara"),
        ("4", "Quality Assessment", "QUAST + BUSCO"),
        ("5", "Repeat Masking", "EDTA"),
        ("6", "Structural Annotation", "Liftoff + Galba + TEtools"),
    ]
    html += '    <table><tr><th>#</th><th>Step</th><th>Tools</th></tr>\n'
    for num, step, tools in steps:
        html += f'      <tr><td>{num}</td><td>{step}</td><td>{tools}</td></tr>\n'
    html += '    </table>\n'
    html += '  </div>\n'
    html += '</section>\n'
    return html


def section_qc(samples, nanoplot_stats_files, quast_tsv_files, busco_files):
    """Section 1: Quality Control (NanoPlot + QUAST + BUSCO)."""
    html = '<section id="qc">\n'
    html += '  <h2>Quality Control</h2>\n'

    # --- NanoPlot ---
    html += '  <h3>1.1 — Raw Read QC (NanoPlot)</h3>\n'
    html += '  <div class="card"><table>\n'
    html += '    <tr><th>Sample</th><th>Mean Read Length</th><th>Mean Read Quality</th><th>Total Bases</th><th>Number of Reads</th></tr>\n'
    for sample, sf in zip(samples, nanoplot_stats_files):
        stats = parse_nanoplot_stats(sf)
        html += f'    <tr><td><strong>{sample}</strong></td>'
        html += f'<td>{stats.get("Mean read length", "N/A")}</td>'
        html += f'<td>{stats.get("Mean read quality", "N/A")}</td>'
        html += f'<td>{stats.get("Total bases", "N/A")}</td>'
        html += f'<td>{stats.get("Number of reads", "N/A")}</td></tr>\n'
    html += '  </table></div>\n'

    # --- QUAST ---
    html += '  <h3>1.2 — Assembly Assessment (QUAST)</h3>\n'
    key_metrics = ["# contigs", "Total length", "Largest contig", "N50", "L50", "GC (%)"]
    html += '  <div class="card"><table>\n'
    header = '<tr><th>Sample</th>'
    for m in key_metrics:
        header += f'<th>{m}</th>'
    header += '</tr>\n'
    html += f'    {header}'
    for sample, qf in zip(samples, quast_tsv_files):
        qdata = parse_quast_tsv(qf)
        html += f'    <tr><td><strong>{sample}</strong></td>'
        for m in key_metrics:
            val = "N/A"
            if m in qdata:
                # prefer "Final_Cleaned" or last column
                vals = list(qdata[m].values())
                val = vals[-1] if vals else "N/A"
            html += f'<td>{val}</td>'
        html += '</tr>\n'
    html += '  </table></div>\n'

    # --- BUSCO ---
    html += '  <h3>1.3 — Genome Completeness (BUSCO)</h3>\n'
    html += '  <div class="card"><table>\n'
    html += '    <tr><th>Sample</th><th>Complete (C)</th><th>Single (S)</th><th>Duplicated (D)</th><th>Fragmented (F)</th><th>Missing (M)</th><th>Total</th></tr>\n'
    for sample, bf in zip(samples, busco_files):
        bdata = parse_busco_summary(bf)
        html += f'    <tr><td><strong>{sample}</strong></td>'
        html += f'<td>{bdata["C"]}</td><td>{bdata["S"]}</td><td>{bdata["D"]}</td>'
        html += f'<td>{bdata["F"]}</td><td>{bdata["M"]}</td><td>{bdata["Total"]}</td></tr>\n'
    html += '  </table></div>\n'

    html += '</section>\n'
    return html


def section_assembly(samples):
    """Section 2: Assembly & Polishing (informational)."""
    html = '<section id="assembly">\n'
    html += '  <h2>Assembly & Polishing</h2>\n'
    html += '  <div class="card">\n'
    html += '    <p>Assemblies were generated and polished using Medaka. '
    html += 'Detailed per-contig statistics are available in the QUAST section above.</p>\n'
    html += '    <table><tr><th>Sample</th><th>Assembly Path</th><th>Polished Path</th></tr>\n'
    for s in samples:
        html += f'    <tr><td>{s}</td>'
        html += f'<td><code>results/{s}/assembly/</code></td>'
        html += f'<td><code>results/{s}/medaka/consensus.fasta</code></td></tr>\n'
    html += '    </table>\n'
    html += '  </div>\n'
    html += '</section>\n'
    return html


def section_decontamination(samples, rejected_files):
    """Section 3: Decontamination (FCS + Tiara)."""
    html = '<section id="decontamination">\n'
    html += '  <h2>Decontamination</h2>\n'
    html += '  <div class="card">\n'
    html += '    <p>Adaptor/vector removal (<strong>FCS-Adaptor</strong>) followed by '
    html += 'biological classification and filtering (<strong>Tiara</strong>). '
    html += 'Only Eukarya + organellar contigs are retained.</p>\n'
    html += '    <table><tr><th>Sample</th><th>Rejected Contigs</th><th>Clean Genome</th></tr>\n'
    for s, rf in zip(samples, rejected_files):
        n_rej = parse_rejected_ids(rf)
        html += f'    <tr><td><strong>{s}</strong></td>'
        html += f'<td>{n_rej}</td>'
        html += f'<td><code>results/{s}/final_genome/final_clean.fasta</code></td></tr>\n'
    html += '    </table>\n'
    html += '  </div>\n'
    html += '</section>\n'
    return html


def parse_repeatmasker_tbl(tbl_file):
    """Parse RepeatMasker .tbl summary into a list of dicts."""
    rows = []
    text = safe_read(tbl_file)
    if not text:
        return rows
    capture = False
    for line in text.splitlines():
        # Start capturing after the dashed separator line
        if line.strip().startswith("---"):
            capture = True
            continue
        if capture and line.strip():
            cols = line.strip().split()
            if len(cols) >= 3 and not cols[0].startswith("="):
                rows.append({
                    "type": cols[0],
                    "count": cols[1] if len(cols) > 1 else "",
                    "bp": cols[2] if len(cols) > 2 else "",
                    "pct": cols[3] if len(cols) > 3 else "",
                })
    return rows


def section_repeats(samples, edta_summary_files, layer2_tbl_files=None):
    """Section 4: Repeat Masking (EDTA + Double-Layer RepeatMasker)."""
    html = '<section id="repeats">\n'
    html += '  <h2>Repeat Masking</h2>\n'

    # --- EDTA ---
    html += '  <h3>EDTA (de novo TE annotation)</h3>\n'
    for sample, sf in zip(samples, edta_summary_files):
        html += f'  <h4 id="sample-{sample}">{sample}</h4>\n'
        rows = parse_edta_summary(sf)
        if rows:
            html += '  <div class="card"><table>\n'
            html += '    <tr><th>Repeat Type</th><th>Count</th><th>Length (bp)</th><th>% of Genome</th></tr>\n'
            for r in rows:
                html += f'    <tr><td>{r["type"]}</td><td>{r["count"]}</td><td>{r["bp"]}</td><td>{r["pct"]}</td></tr>\n'
            html += '  </table></div>\n'
        else:
            html += '  <div class="card"><p>EDTA summary not available or could not be parsed.</p></div>\n'

    # --- Double-Layer RepeatMasker ---
    if layer2_tbl_files:
        html += '  <h3>Double-Layer RepeatMasker (Layer 2 — Curated Library)</h3>\n'
        for sample, tf in zip(samples, layer2_tbl_files):
            html += f'  <h4>{sample}</h4>\n'
            tbl_text = safe_read(tf)
            if tbl_text:
                html += f'  <div class="card"><pre>{tbl_text}</pre></div>\n'
            else:
                html += '  <div class="card"><p>Layer 2 RepeatMasker summary not available.</p></div>\n'

    html += '</section>\n'
    return html


def section_annotation(samples, liftoff_files, galba_files, stats_files):
    """Section 5: Annotation (Liftoff + Galba + stats)."""
    html = '<section id="annotation">\n'
    html += '  <h2>Structural Annotation</h2>\n'

    # Comparison table
    html += '  <h3>Gene Count Comparison</h3>\n'
    html += '  <div class="card"><table>\n'
    html += '    <tr><th>Sample</th><th>Liftoff Genes</th><th>Liftoff mRNAs</th>'
    html += '<th>Galba Genes</th><th>Galba mRNAs</th></tr>\n'
    for sample, lf, gf in zip(samples, liftoff_files, galba_files):
        ls = parse_gff_stats(lf)
        gs = parse_gff_stats(gf)
        html += f'    <tr><td><strong>{sample}</strong></td>'
        html += f'<td>{ls["genes"]}</td><td>{ls["mrnas"]}</td>'
        html += f'<td>{gs["genes"]}</td><td>{gs["mrnas"]}</td></tr>\n'
    html += '  </table></div>\n'

    # Per-sample stats
    html += '  <h3>Detailed Stats per Sample</h3>\n'
    for sample, sf in zip(samples, stats_files):
        text = parse_annotation_stats_txt(sf)
        html += f'  <div class="card"><h4>{sample}</h4><pre>{text}</pre></div>\n'

    html += '</section>\n'
    return html


def section_summary(samples):
    """Section 6: Pipeline Summary footer."""
    html = '<section id="summary">\n'
    html += '  <h2>Pipeline Summary</h2>\n'
    html += '  <div class="card">\n'
    html += '    <p>All files for each sample are stored under <code>results/&lt;sample&gt;/</code>:</p>\n'
    html += '    <table><tr><th>Subdirectory</th><th>Contents</th></tr>\n'
    dirs_info = [
        ("qc/nanoplot/", "NanoPlot raw read QC"),
        ("assembly/", "Raw assembly (Flye/Hifiasm)"),
        ("medaka/", "Polished consensus"),
        ("decontamination/fcs/", "FCS adaptor screening & cleaning"),
        ("decontamination/tiara/", "Tiara classification"),
        ("final_genome/", "Clean genome FASTA"),
        ("qc/quast/", "QUAST assembly assessment"),
        ("qc/busco/", "BUSCO completeness"),
        ("repeats/", "EDTA + Double-Layer RepeatMasker masking & library"),
        ("repeats/repeatmodeler/", "RepeatModeler de novo TE library"),
        ("repeats/layer1/", "Layer 1 masking (RepeatModeler library)"),
        ("repeats/layer2/", "Layer 2 masking (curated TE library)"),
        ("annotation/", "Liftoff, Galba structural annotation"),
    ]
    for d, desc in dirs_info:
        html += f'    <tr><td><code>{d}</code></td><td>{desc}</td></tr>\n'
    html += '    </table>\n'
    html += '  </div>\n'
    html += '</section>\n'
    return html


def generate_report(samples, nanoplot_stats, quast_tsvs, busco_summaries,
                    rejected_ids, edta_summaries, liftoff_gffs, galba_gffs,
                    annotation_stats, output_file, layer2_tbls=None):
    """Assemble the full indexed HTML report."""
    html = "<!DOCTYPE html>\n<html lang='en'>\n<head>\n"
    html += "  <meta charset='UTF-8'>\n"
    html += "  <meta name='viewport' content='width=device-width, initial-scale=1.0'>\n"
    html += "  <title>PlantGenotationFlow Report</title>\n"
    html += f"  <style>{CSS}</style>\n"
    html += "</head>\n<body>\n"

    # Sidebar
    html += build_sidebar(samples)

    # Main content
    html += '<div class="main">\n'
    html += '  <h1>PlantGenotationFlow Report</h1>\n'
    html += f'  <p class="subtitle">Generated {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>\n'

    html += section_overview(samples)
    html += section_qc(samples, nanoplot_stats, quast_tsvs, busco_summaries)
    html += section_assembly(samples)
    html += section_decontamination(samples, rejected_ids)
    html += section_repeats(samples, edta_summaries, layer2_tbls)
    html += section_annotation(samples, liftoff_gffs, galba_gffs, annotation_stats)
    html += section_summary(samples)

    html += '<footer>PlantGenotationFlow &mdash; Genome Annotation Pipeline Report</footer>\n'
    html += '</div>\n</body>\n</html>\n'

    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    with open(output_file, "w") as fh:
        fh.write(html)
    print(f"Report written to {output_file}")


# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

def main_snakemake(snakemake):
    """Called when invoked via Snakemake `script:` directive."""
    samples = snakemake.params.sample_names
    generate_report(
        samples=samples,
        nanoplot_stats=snakemake.input.nanoplot_stats,
        quast_tsvs=snakemake.input.quast_tsvs,
        busco_summaries=snakemake.input.busco_summaries,
        rejected_ids=snakemake.input.rejected_ids,
        edta_summaries=snakemake.input.edta_summaries,
        liftoff_gffs=snakemake.input.liftoff_gffs,
        galba_gffs=snakemake.input.galba_gffs,
        annotation_stats=snakemake.input.annotation_stats,
        output_file=snakemake.output.html,
        layer2_tbls=snakemake.input.layer2_tbls,
    )


def main_cli():
    """Command-line interface."""
    parser = argparse.ArgumentParser(description="Generate PlantGenotationFlow HTML report")
    parser.add_argument("--samples", nargs="+", required=True)
    parser.add_argument("--nanoplot-stats", nargs="+", required=True)
    parser.add_argument("--quast-tsvs", nargs="+", required=True)
    parser.add_argument("--busco-summaries", nargs="+", required=True)
    parser.add_argument("--rejected-ids", nargs="+", required=True)
    parser.add_argument("--edta-summaries", nargs="+", required=True)
    parser.add_argument("--liftoff-gffs", nargs="+", required=True)
    parser.add_argument("--galba-gffs", nargs="+", required=True)
    parser.add_argument("--annotation-stats", nargs="+", required=True)
    parser.add_argument("--layer2-tbls", nargs="+", default=None)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    generate_report(
        samples=args.samples,
        nanoplot_stats=args.nanoplot_stats,
        quast_tsvs=args.quast_tsvs,
        busco_summaries=args.busco_summaries,
        rejected_ids=args.rejected_ids,
        edta_summaries=args.edta_summaries,
        liftoff_gffs=args.liftoff_gffs,
        galba_gffs=args.galba_gffs,
        annotation_stats=args.annotation_stats,
        output_file=args.output,
        layer2_tbls=args.layer2_tbls,
    )


# Snakemake script directive auto-injects `snakemake` into global scope
try:
    main_snakemake(snakemake)  # noqa: F821
except NameError:
    if __name__ == "__main__":
        main_cli()
