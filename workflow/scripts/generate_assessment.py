import pandas as pd
import argparse
import os

def generate_html_report(quast_files, busco_files, samples, output_file):
    html_content = """
    <html>
    <head>
        <title>Genome Assessment Report</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            h1 { color: #333; }
            table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background-color: #f2f2f2; }
            tr:nth-child(even) { background-color: #f9f9f9; }
        </style>
    </head>
    <body>
        <h1>Genome Assessment Report</h1>
    """

    # --- QUAST Section ---
    html_content += "<h2>QUAST Statistics</h2>"
    html_content += "<table><tr><th>Sample</th><th>N50</th><th>L50</th><th>Total Length</th><th># Contigs</th></tr>"

    for i, sample in enumerate(samples):
        quast_file = quast_files[i]
        try:
            # QUAST TSV format parsing
            df = pd.read_csv(quast_file, sep='\t', index_col=0)
            # Assuming 'Final_Cleaned' column exists if we compared draft vs final
            # Or use the first column if only one assembly
            
            # Simple check to find the column with stats
            col_to_use = df.columns[0] # Default
            for col in df.columns:
                if 'Final' in col or 'clean' in col.lower():
                    col_to_use = col
                    break
            
            n50 = df.loc['N50', col_to_use] if 'N50' in df.index else 'N/A'
            l50 = df.loc['L50', col_to_use] if 'L50' in df.index else 'N/A'
            tot_len = df.loc['Total length', col_to_use] if 'Total length' in df.index else 'N/A'
            n_contigs = df.loc['# contigs', col_to_use] if '# contigs' in df.index else 'N/A'

            html_content += f"<tr><td>{sample}</td><td>{n50}</td><td>{l50}</td><td>{tot_len}</td><td>{n_contigs}</td></tr>"
        except Exception as e:
            html_content += f"<tr><td>{sample}</td><td colspan='4'>Error: {str(e)}</td></tr>"

    html_content += "</table>"

    # --- BUSCO Section ---
    html_content += "<h2>BUSCO Completeness</h2>"
    html_content += "<table><tr><th>Sample</th><th>Complete (C)</th><th>Single (S)</th><th>Duplicated (D)</th><th>Fragmented (F)</th><th>Missing (M)</th></tr>"

    for i, sample in enumerate(samples):
        busco_file = busco_files[i]
        try:
            # Parse BUSCO short summary
            c, s, d, f, m = "N/A", "N/A", "N/A", "N/A", "N/A"
            with open(busco_file, 'r') as fh:
                for line in fh:
                    if "C:" in line and "S:" in line:
                         # Format example: C:90.0%[S:85.0%,D:5.0%],F:5.0%,M:5.0%,n:1000
                         # This is rough parsing, better to rely on specific lines if standard summary
                        pass
                    if "Complete BUSCOs (C)" in line:
                         c = line.strip().split('\t')[0]
                    elif "Complete and single-copy BUSCOs (S)" in line:
                         s = line.strip().split('\t')[0]
                    elif "Complete and duplicated BUSCOs (D)" in line:
                         d = line.strip().split('\t')[0]
                    elif "Fragmented BUSCOs (F)" in line:
                         f = line.strip().split('\t')[0]
                    elif "Missing BUSCOs (M)" in line:
                         m = line.strip().split('\t')[0]
            
            html_content += f"<tr><td>{sample}</td><td>{c}</td><td>{s}</td><td>{d}</td><td>{f}</td><td>{m}</td></tr>"
        except Exception as e:
             html_content += f"<tr><td>{sample}</td><td colspan='5'>Error: {str(e)}</td></tr>"

    html_content += "</table></body></html>"

    with open(output_file, "w") as f:
        f.write(html_content)

if __name__ == "__main__":
    # If called via Snakemake script directive
    # Snakemake injects 'snakemake' object
    try:
        generate_html_report(
            snakemake.input.quast_files,
            snakemake.input.busco_files,
            snakemake.params.sample_names,
            snakemake.output.html
        )
    except NameError:
        # Standalone testing not implemented here
        print("This script is intended to be run via Snakemake.")
