#!/usr/bin/env python3
"""
PlantGenotationFlow — Per-Sample Standalone Report Generator
=============================================================
Generates a single-page HTML report per sample with sidebar navigation
covering: NanoPlot QC, BUSCO, QUAST, Decontamination, Repeats,
RepeatModeler, and Annotation sections.

The report folder is standalone — all referenced files are relative to the
report directory.

Called from the Snakemake rule via shell directive:
    python workflow/scripts/generate_pipeline_report.py \\
        --sample {sample} --report-dir {report_dir} \\
        --repeat-method {method} --annotation-method {method} \\
        --output {output}
"""

import argparse
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


def safe_read_head(path, max_lines=30):
    """Read first N lines of a file."""
    try:
        with open(path, "r") as fh:
            lines = []
            for i, line in enumerate(fh):
                if i >= max_lines:
                    break
                lines.append(line)
            return "".join(lines)
    except Exception:
        return None


def count_lines(path):
    """Count total lines in a file."""
    try:
        with open(path, "r") as fh:
            return sum(1 for _ in fh)
    except Exception:
        return 0


def html_escape(text):
    """Basic HTML escaping."""
    if not text:
        return ""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ---------------------------------------------------------------------------
# CSS & JS
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
h1 { font-size: 28px; margin-bottom: 6px; }
.subtitle { color: var(--text-muted); margin-bottom: 32px; font-size: 14px; }
section { margin-bottom: 48px; }
section h2 {
    font-size: 22px;
    margin-bottom: 4px;
    padding-bottom: 8px;
    border-bottom: 2px solid var(--accent);
    display: inline-block;
}
section h3 { font-size: 17px; margin: 20px 0 10px; color: var(--text-muted); }
.card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 20px 24px;
    margin: 14px 0;
    box-shadow: 0 1px 3px rgba(0,0,0,0.04);
}
table { width: 100%; border-collapse: collapse; font-size: 14px; margin: 10px 0; }
th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--border); }
th {
    background: #f1f5f9; font-weight: 600; font-size: 13px;
    text-transform: uppercase; letter-spacing: 0.3px; color: var(--text-muted);
}
tr:hover td { background: #f8fafc; }
.badge {
    display: inline-block; padding: 2px 10px; border-radius: 12px;
    font-size: 12px; font-weight: 600;
}
.badge-success { background: #dcfce7; color: #166534; }
.badge-warning { background: #fef9c3; color: #854d0e; }
.badge-danger  { background: #fee2e2; color: #991b1b; }
.badge-info    { background: #dbeafe; color: #1e40af; }
pre {
    background: #1e293b; color: #e2e8f0; padding: 16px;
    border-radius: 8px; font-size: 13px; overflow-x: auto;
    white-space: pre-wrap; word-wrap: break-word;
    max-height: 600px; overflow-y: auto;
}
.metric-grid {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 14px; margin: 14px 0;
}
.metric-box {
    background: var(--card-bg); border: 1px solid var(--border);
    border-radius: 10px; padding: 16px; text-align: center;
}
.metric-box .value { font-size: 28px; font-weight: 700; color: var(--accent); }
.metric-box .label { font-size: 12px; color: var(--text-muted); margin-top: 4px; }
.sample-tag {
    display: inline-block; background: var(--accent); color: #fff;
    padding: 3px 12px; border-radius: 14px; font-size: 13px; font-weight: 600;
}
.link-card {
    display: inline-block; padding: 10px 20px; margin: 6px 8px 6px 0;
    background: var(--accent); color: #fff; text-decoration: none;
    border-radius: 8px; font-size: 14px; font-weight: 500;
    transition: background 0.2s;
}
.link-card:hover { background: #0284c7; }
.bar-container {
    display: flex; width: 100%; height: 40px; background-color: #e2e8f0;
    border-radius: 6px; overflow: hidden; margin: 10px 0;
}
.bar-seg {
    height: 100%; text-align: center; color: white;
    font-size: 12px; line-height: 40px; font-weight: 600;
}
.c-s { background-color: #22c55e; }
.c-d { background-color: #16a34a; }
.frag { background-color: #f59e0b; }
.miss { background-color: #ef4444; }
.tab-container { margin: 14px 0; }
.tab-buttons { display: flex; gap: 4px; margin-bottom: -1px; position: relative; z-index: 1; }
.tab-btn {
    padding: 8px 16px; border: 1px solid var(--border); border-bottom: none;
    border-radius: 8px 8px 0 0; background: #f1f5f9; cursor: pointer;
    font-size: 13px; font-weight: 500; color: var(--text-muted);
}
.tab-btn.active { background: var(--card-bg); color: var(--text); border-bottom: 1px solid var(--card-bg); }
.tab-content {
    display: none; border: 1px solid var(--border);
    border-radius: 0 8px 8px 8px; padding: 16px; background: var(--card-bg);
}
.tab-content.active { display: block; }
footer {
    text-align: center; color: var(--text-muted); font-size: 12px;
    padding: 24px 0; border-top: 1px solid var(--border); margin-top: 40px;
}
"""

JS = """
function openTab(evt, tabId) {
    var container = evt.target.closest('.tab-container');
    container.querySelectorAll('.tab-content').forEach(function(c) { c.classList.remove('active'); });
    container.querySelectorAll('.tab-btn').forEach(function(b) { b.classList.remove('active'); });
    document.getElementById(tabId).classList.add('active');
    evt.target.classList.add('active');
}
"""


# ---------------------------------------------------------------------------
# Section builders
# ---------------------------------------------------------------------------

def build_sidebar(sample):
    """Generate sidebar navigation HTML."""
    nav = '<div class="sidebar">\n'
    nav += '  <h2>&#127807; PlantGenotationFlow</h2>\n'
    nav += f'  <div class="nav-section">Sample: {sample}</div>\n'
    links = [
        ("overview", "Overview"),
        ("nanoplot", "NanoPlot QC"),
        ("busco", "BUSCO"),
        ("quast", "QUAST"),
        ("decontamination", "Decontamination"),
        ("repeats", "Repeat Masking"),
        ("repeatmodeler", "RepeatModeler"),
        ("annotation", "Annotation"),
    ]
    for href, label in links:
        nav += f'  <a href="#{href}">{label}</a>\n'
    nav += '</div>\n'
    return nav


def section_overview(sample):
    """Section: Overview."""
    html = '<section id="overview">\n'
    html += '  <h2>Overview</h2>\n'
    html += '  <div class="card">\n'
    html += f'    <p>Standalone pipeline report for sample '
    html += f'<span class="sample-tag">{sample}</span></p>\n'
    html += f'    <p><strong>Report generated:</strong> '
    html += f'{datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>\n'
    html += '    <p>This folder contains all reports needed for visualization. '
    html += 'Open sub-reports (NanoPlot, QUAST, Icarus) by clicking their links below.</p>\n'
    html += '  </div>\n'

    html += '  <div class="card">\n'
    html += '    <h3>Pipeline Sections</h3>\n'
    steps = [
        ("1", "Raw Read QC", "NanoPlot"),
        ("2", "Genome Completeness", "BUSCO"),
        ("3", "Assembly Assessment", "QUAST + Icarus"),
        ("4", "Decontamination", "FCS-Adaptor + Tiara"),
        ("5", "Repeat Masking", "RepeatMasker (Layer 1 + Layer 2)"),
        ("6", "Repeat Modeling", "RepeatModeler (de novo TE library)"),
        ("7", "Structural Annotation", "GALBA / Liftoff"),
    ]
    html += '    <table><tr><th>#</th><th>Step</th><th>Tools</th></tr>\n'
    for num, step, tools in steps:
        html += f'      <tr><td>{num}</td><td>{step}</td><td>{tools}</td></tr>\n'
    html += '    </table>\n'
    html += '  </div>\n'
    html += '</section>\n'
    return html


def section_nanoplot(report_dir):
    """Section: NanoPlot raw read QC."""
    html = '<section id="nanoplot">\n'
    html += '  <h2>NanoPlot &mdash; Raw Read QC</h2>\n'

    # Parse stats
    stats_file = os.path.join(report_dir, "nanoplot", "NanoStats.txt")
    stats_post_file = os.path.join(report_dir, "nanoplot",
                                   "NanoStats_post_filtering.txt")
    stats_text = safe_read(stats_file)
    stats_post_text = safe_read(stats_post_file)

    if stats_text:
        # Parse key metrics
        metrics = {}
        for line in stats_text.strip().splitlines():
            parts = line.split(":")
            if len(parts) == 2:
                metrics[parts[0].strip()] = parts[1].strip()

        # Display key metrics as boxes
        key_metrics = [
            ("Number of reads", "Total Reads"),
            ("Total bases", "Total Bases"),
            ("Mean read length", "Mean Length"),
            ("Mean read quality", "Mean Quality"),
            ("Median read length", "Median Length"),
            ("Read length N50", "N50"),
        ]
        html += '  <div class="metric-grid">\n'
        for key, label in key_metrics:
            val = metrics.get(key, "N/A")
            html += (f'    <div class="metric-box">'
                     f'<div class="value">{val}</div>'
                     f'<div class="label">{label}</div></div>\n')
        html += '  </div>\n'

    # Show full stats in tabs
    if stats_text or stats_post_text:
        html += '  <div class="tab-container">\n'
        html += '    <div class="tab-buttons">\n'
        if stats_text:
            html += ('      <button class="tab-btn active" '
                     'onclick="openTab(event, \'nano-pre\')">'
                     'Pre-filtering Stats</button>\n')
        if stats_post_text:
            cls = "" if stats_text else " active"
            html += (f'      <button class="tab-btn{cls}" '
                     f'onclick="openTab(event, \'nano-post\')">'
                     f'Post-filtering Stats</button>\n')
        html += '    </div>\n'
        if stats_text:
            html += (f'    <div id="nano-pre" class="tab-content active">'
                     f'<pre>{html_escape(stats_text)}</pre></div>\n')
        if stats_post_text:
            cls = "" if stats_text else " active"
            html += (f'    <div id="nano-post" class="tab-content{cls}">'
                     f'<pre>{html_escape(stats_post_text)}</pre></div>\n')
        html += '  </div>\n'

    # Links to NanoPlot HTML files
    nanoplot_dir = os.path.join(report_dir, "nanoplot")
    if os.path.isdir(nanoplot_dir):
        html_files = sorted(
            f for f in os.listdir(nanoplot_dir) if f.endswith(".html")
        )
        if html_files:
            html += '  <h3>Interactive Reports &amp; Plots</h3>\n'
            html += '  <div class="card">\n'
            for f in html_files:
                label = f.replace(".html", "").replace("_", " ")
                html += (f'    <a class="link-card" href="nanoplot/{f}" '
                         f'target="_blank">{label}</a>\n')
            html += '  </div>\n'

    if not stats_text and not stats_post_text:
        html += ('  <div class="card">'
                 '<p>NanoPlot statistics not available.</p></div>\n')

    html += '</section>\n'
    return html


def section_busco(report_dir):
    """Section: BUSCO genome completeness."""
    html = '<section id="busco">\n'
    html += '  <h2>BUSCO &mdash; Genome Completeness</h2>\n'

    busco_file = os.path.join(report_dir, "busco", "short_summary.txt")
    text = safe_read(busco_file)

    if text:
        # Parse BUSCO percentages for visual bar
        match = re.search(
            r'C:([\d.]+)%\[S:([\d.]+)%,D:([\d.]+)%\],F:([\d.]+)%,M:([\d.]+)%',
            text,
        )
        if match:
            c, s, d, f, m = [float(x) for x in match.groups()]

            # Stacked bar chart
            html += '  <div class="card">\n'
            html += '    <h3>Completeness Overview</h3>\n'
            html += '    <div class="bar-container">\n'
            s_label = f"S:{s}%" if s > 3 else ""
            d_label = f"D:{d}%" if d > 3 else ""
            html += (f'      <div class="bar-seg c-s" style="width:{s}%;" '
                     f'title="Single-copy: {s}%">{s_label}</div>\n')
            html += (f'      <div class="bar-seg c-d" style="width:{d}%;" '
                     f'title="Duplicated: {d}%">{d_label}</div>\n')
            html += (f'      <div class="bar-seg frag" style="width:{f}%;" '
                     f'title="Fragmented: {f}%"></div>\n')
            html += (f'      <div class="bar-seg miss" style="width:{m}%;" '
                     f'title="Missing: {m}%"></div>\n')
            html += '    </div>\n'
            html += '    <p style="font-size:13px; margin-top:8px;">\n'
            html += f'      <span class="badge badge-success">Complete: {c}%</span> '
            html += f'      <span class="badge badge-info">Single-copy: {s}%</span> '
            html += f'      <span class="badge badge-info">Duplicated: {d}%</span> '
            html += f'      <span class="badge badge-warning">Fragmented: {f}%</span> '
            html += f'      <span class="badge badge-danger">Missing: {m}%</span>\n'
            html += '    </p>\n'
            html += '  </div>\n'

        # Parse BUSCO counts table
        count_rows = []
        for line in text.splitlines():
            stripped = line.strip()
            if "\t" in stripped and "BUSCOs" in stripped:
                parts = stripped.split("\t")
                if len(parts) >= 2:
                    count_rows.append(
                        (parts[0].strip(), "\t".join(parts[1:]).strip())
                    )
            elif "Total BUSCO groups" in stripped:
                parts = stripped.split("\t")
                if len(parts) >= 2:
                    count_rows.append(
                        (parts[0].strip(), "\t".join(parts[1:]).strip())
                    )

        if count_rows:
            html += '  <div class="card">\n'
            html += '    <h3>BUSCO Counts</h3>\n'
            html += '    <table><tr><th>Count</th><th>Category</th></tr>\n'
            for cnt, cat in count_rows:
                html += (f'      <tr><td><strong>{cnt}</strong></td>'
                         f'<td>{cat}</td></tr>\n')
            html += '    </table>\n'
            html += '  </div>\n'

        # Full summary text
        html += '  <div class="card">\n'
        html += '    <h3>Full Summary</h3>\n'
        html += f'    <pre>{html_escape(text)}</pre>\n'
        html += '  </div>\n'
    else:
        html += ('  <div class="card">'
                 '<p>BUSCO summary not available.</p></div>\n')

    html += '</section>\n'
    return html


def section_quast(report_dir):
    """Section: QUAST assembly assessment."""
    html = '<section id="quast">\n'
    html += '  <h2>QUAST &mdash; Assembly Assessment</h2>\n'

    # Parse report.tsv for inline table display
    tsv_file = os.path.join(report_dir, "quast", "report.tsv")
    tsv_text = safe_read(tsv_file)

    if tsv_text:
        lines = tsv_text.strip().splitlines()
        if len(lines) > 1:
            headers = lines[0].split("\t")
            html += '  <div class="card">\n'
            html += '    <h3>Assembly Statistics</h3>\n'
            html += '    <table>\n'
            html += ('      <tr>'
                     + ''.join(f'<th>{html_escape(h)}</th>' for h in headers)
                     + '</tr>\n')
            for line in lines[1:]:
                cols = line.split("\t")
                html += ('      <tr>'
                         + ''.join(f'<td>{html_escape(c)}</td>' for c in cols)
                         + '</tr>\n')
            html += '    </table>\n'
            html += '  </div>\n'

    # Links to HTML reports
    html += '  <h3>Interactive Reports</h3>\n'
    html += '  <div class="card">\n'

    quast_report = os.path.join(report_dir, "quast", "report.html")
    icarus_report = os.path.join(report_dir, "quast", "icarus.html")

    if os.path.isfile(quast_report):
        html += ('    <a class="link-card" href="quast/report.html" '
                 'target="_blank">&#128202; QUAST Report</a>\n')
    if os.path.isfile(icarus_report):
        html += ('    <a class="link-card" href="quast/icarus.html" '
                 'target="_blank">&#128300; Icarus Viewer</a>\n')

    if not os.path.isfile(quast_report) and not os.path.isfile(icarus_report):
        html += '    <p>No interactive QUAST reports found.</p>\n'

    html += '  </div>\n'
    html += '</section>\n'
    return html


def section_decontamination(report_dir):
    """Section: Decontamination (Tiara classification + rejected IDs)."""
    html = '<section id="decontamination">\n'
    html += '  <h2>Decontamination</h2>\n'
    html += '  <div class="card">\n'
    html += '    <p>Biological classification using <strong>Tiara</strong>. '
    html += 'Non-eukaryotic contigs (bacteria, archaea, unknown) are filtered out. '
    html += 'Only eukarya + organellar contigs are retained.</p>\n'
    html += '  </div>\n'

    # Tiara classification log
    log_file = os.path.join(report_dir, "decontamination",
                            "log_classification.txt")
    log_text = safe_read(log_file)
    if log_text:
        html += '  <h3>Classification Summary (Tiara)</h3>\n'
        html += (f'  <div class="card">'
                 f'<pre>{html_escape(log_text)}</pre></div>\n')

    # Rejected IDs - show top rows + total count
    rejected_file = os.path.join(report_dir, "decontamination",
                                 "rejected_ids.txt")
    total = count_lines(rejected_file)
    if total > 0:
        rejected_head = safe_read_head(rejected_file, 30)
        html += (f'  <h3>Rejected Contigs '
                 f'<span class="badge badge-danger">{total} total</span>'
                 f'</h3>\n')
        if rejected_head:
            # Try to show as table (TSV format)
            lines = rejected_head.strip().splitlines()
            if lines and "\t" in lines[0]:
                headers = lines[0].split("\t")
                html += '  <div class="card">\n'
                html += (f'    <p><em>Showing first 30 entries '
                         f'of {total}</em></p>\n')
                html += '    <table>\n'
                html += ('      <tr>'
                         + ''.join(f'<th>{html_escape(h)}</th>'
                                   for h in headers)
                         + '</tr>\n')
                for line in lines[1:]:
                    cols = line.split("\t")
                    html += ('      <tr>'
                             + ''.join(f'<td>{html_escape(c)}</td>'
                                       for c in cols)
                             + '</tr>\n')
                html += '    </table>\n'
                html += '  </div>\n'
            else:
                html += (f'  <div class="card">'
                         f'<pre>{html_escape(rejected_head)}</pre></div>\n')
    else:
        html += ('  <div class="card">'
                 '<p>No rejected contigs data available.</p></div>\n')

    html += '</section>\n'
    return html


def section_repeats(report_dir, repeat_method):
    """Section: Repeat Masking (Layer 1 + Layer 2 or EDTA)."""
    html = '<section id="repeats">\n'
    html += '  <h2>Repeat Masking</h2>\n'
    html += (f'  <div class="card"><p><strong>Method:</strong> '
             f'<span class="badge badge-info">'
             f'{repeat_method.upper()}</span></p></div>\n')

    if repeat_method == "tetools":
        # Layer 1 — RepeatModeler de novo library
        layer1_file = os.path.join(report_dir, "repeats", "genome.fa.tbl")
        layer1_text = safe_read(layer1_file)
        if layer1_text:
            html += ('  <h3>Layer 1 &mdash; '
                     'RepeatModeler Library (de novo)</h3>\n')
            html += '  <div class="card">\n'
            html += ('    <p>Masking with de novo TE library '
                     'built by RepeatModeler.</p>\n')
            html += f'    <pre>{html_escape(layer1_text)}</pre>\n'
            html += '  </div>\n'

        # Layer 2 — Curated TE library
        layer2_file = os.path.join(report_dir, "repeats",
                                   "genome.masked.fa.tbl")
        layer2_text = safe_read(layer2_file)
        if layer2_text:
            html += '  <h3>Layer 2 &mdash; Curated TE Library</h3>\n'
            html += '  <div class="card">\n'
            html += ('    <p>Additional masking with curated TE library '
                     'on the Layer 1 masked genome.</p>\n')
            html += f'    <pre>{html_escape(layer2_text)}</pre>\n'
            html += '  </div>\n'

        if not layer1_text and not layer2_text:
            html += ('  <div class="card"><p>RepeatMasker summary '
                     'tables not available.</p></div>\n')
    else:
        # EDTA summary
        edta_file = os.path.join(report_dir, "repeats", "edta_summary.txt")
        edta_text = safe_read(edta_file)
        if edta_text:
            html += '  <h3>EDTA Summary</h3>\n'
            html += (f'  <div class="card">'
                     f'<pre>{html_escape(edta_text)}</pre></div>\n')
        else:
            html += ('  <div class="card">'
                     '<p>EDTA summary not available.</p></div>\n')

    html += '</section>\n'
    return html


def section_repeatmodeler(report_dir):
    """Section: RepeatModeler log."""
    html = '<section id="repeatmodeler">\n'
    html += '  <h2>RepeatModeler</h2>\n'
    html += '  <div class="card">\n'
    html += ('    <p>De novo transposable element library construction '
             'using RepeatModeler.</p>\n')
    html += '  </div>\n'

    log_file = os.path.join(report_dir, "repeats", "repeatmodeler.log")
    log_text = safe_read(log_file)
    if log_text:
        html += '  <div class="card">\n'
        html += '    <h3>RepeatModeler Run Log</h3>\n'
        html += f'    <pre>{html_escape(log_text)}</pre>\n'
        html += '  </div>\n'
    else:
        html += ('  <div class="card">'
                 '<p>RepeatModeler log not available.</p></div>\n')

    html += '</section>\n'
    return html


def section_annotation(report_dir, annotation_method):
    """Section: Structural Annotation."""
    html = '<section id="annotation">\n'
    html += '  <h2>Structural Annotation</h2>\n'
    html += (f'  <div class="card"><p><strong>Method:</strong> '
             f'<span class="badge badge-info">'
             f'{annotation_method.upper()}</span></p></div>\n')

    stats_file = os.path.join(report_dir, "annotation", "stats.txt")
    stats_text = safe_read(stats_file)

    if stats_text:
        # Try to extract gene count for a metric box
        gene_count = None
        prev_line = ""
        for line in stats_text.splitlines():
            stripped = line.strip()
            # Look for a number after "Gene Count" header
            if stripped.isdigit() and "Gene Count" in prev_line:
                gene_count = stripped
                break
            match = re.search(r'Gene Count[:\s]+(\d+)',
                              stripped, re.IGNORECASE)
            if match:
                gene_count = match.group(1)
                break
            prev_line = stripped

        if gene_count:
            html += '  <div class="metric-grid">\n'
            html += (f'    <div class="metric-box">'
                     f'<div class="value">{gene_count}</div>'
                     f'<div class="label">Predicted Genes</div></div>\n')
            html += '  </div>\n'

        html += '  <div class="card">\n'
        html += '    <h3>Annotation Statistics</h3>\n'
        html += f'    <pre>{html_escape(stats_text)}</pre>\n'
        html += '  </div>\n'
    else:
        html += ('  <div class="card">'
                 '<p>Annotation statistics not available.</p></div>\n')

    html += '</section>\n'
    return html


# ---------------------------------------------------------------------------
# Report assembly
# ---------------------------------------------------------------------------

def generate_report(sample, report_dir, repeat_method,
                    annotation_method, output_file):
    """Assemble the full standalone per-sample HTML report."""
    html = "<!DOCTYPE html>\n<html lang='en'>\n<head>\n"
    html += "  <meta charset='UTF-8'>\n"
    html += ("  <meta name='viewport' "
             "content='width=device-width, initial-scale=1.0'>\n")
    html += f"  <title>PlantGenotationFlow &mdash; {sample}</title>\n"
    html += f"  <style>{CSS}</style>\n"
    html += f"  <script>{JS}</script>\n"
    html += "</head>\n<body>\n"

    # Sidebar
    html += build_sidebar(sample)

    # Main content
    html += '<div class="main">\n'
    html += f'  <h1>PlantGenotationFlow &mdash; {sample}</h1>\n'
    html += (f'  <p class="subtitle">Generated '
             f'{datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>\n')

    html += section_overview(sample)
    html += section_nanoplot(report_dir)
    html += section_busco(report_dir)
    html += section_quast(report_dir)
    html += section_decontamination(report_dir)
    html += section_repeats(report_dir, repeat_method)
    html += section_repeatmodeler(report_dir)
    html += section_annotation(report_dir, annotation_method)

    html += ('<footer>PlantGenotationFlow &mdash; '
             'Genome Annotation Pipeline Report</footer>\n')
    html += '</div>\n</body>\n</html>\n'

    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)
    with open(output_file, "w") as fh:
        fh.write(html)
    print(f"[generate_pipeline_report] Report written to {output_file}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Generate per-sample standalone PlantGenotationFlow report"
    )
    parser.add_argument("--sample", required=True, help="Sample name")
    parser.add_argument("--report-dir", required=True,
                        help="Report directory with collected files")
    parser.add_argument("--repeat-method", default="edta",
                        choices=["edta", "tetools"])
    parser.add_argument("--annotation-method", default="both",
                        choices=["liftoff", "galba", "both"])
    parser.add_argument("--output", required=True, help="Output HTML path")
    args = parser.parse_args()
    generate_report(
        sample=args.sample,
        report_dir=args.report_dir,
        repeat_method=args.repeat_method,
        annotation_method=args.annotation_method,
        output_file=args.output,
    )


if __name__ == "__main__":
    main()
