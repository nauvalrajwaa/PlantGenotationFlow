import sys
import os
import pandas as pd
import re
import argparse

def parse_quast(file_path, sample_name):
    """Membaca file report.tsv dari QUAST"""
    try:
        # QUAST report.tsv biasanya baris=metrik, kolom=assembly
        df = pd.read_csv(file_path, sep="\t", index_col=0)
        # Kita ambil kolom pertama (biasanya nama assembly)
        data = df.iloc[:, 0].to_dict()
        data['Sample'] = sample_name
        return data
    except Exception as e:
        print(f"Error reading QUAST {file_path}: {e}")
        return None

def parse_busco(file_path, sample_name):
    """Membaca short_summary.txt dari BUSCO"""
    data = {'Sample': sample_name}
    try:
        with open(file_path, 'r') as f:
            content = f.read()
            # Regex untuk menangkap angka C, S, D, F, M
            # Format: C:90.0%[S:85.0%,D:5.0%],F:5.0%,M:5.0%
            match = re.search(r'C:([\d\.]+)%\[S:([\d\.]+)%,D:([\d\.]+)%\],F:([\d\.]+)%,M:([\d\.]+)%', content)
            if match:
                data['Complete'] = float(match.group(1))
                data['Single'] = float(match.group(2))
                data['Duplicated'] = float(match.group(3))
                data['Fragmented'] = float(match.group(4))
                data['Missing'] = float(match.group(5))
    except Exception as e:
        print(f"Error reading BUSCO {file_path}: {e}")
    return data

def generate_html(quast_df, busco_df, output_file):
    """Membuat HTML Report"""
    
    # CSS Styling
    style = """
    <style>
        body { font-family: sans-serif; margin: 20px; background-color: #f4f4f4; }
        .container { background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1, h2 { color: #333; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #007bff; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        
        /* Stacked Bar Chart CSS */
        .bar-container { display: flex; width: 100%; height: 30px; background-color: #ddd; border-radius: 4px; overflow: hidden; margin-top: 5px; }
        .bar-seg { height: 100%; text-align: center; color: white; font-size: 12px; line-height: 30px; }
        .c-s { background-color: #66bd63; } /* Single */
        .c-d { background-color: #1a9850; } /* Duplicated */
        .frag { background-color: #fdae61; } /* Fragmented */
        .miss { background-color: #d73027; } /* Missing */
    </style>
    """
    
    html = [f"<html><head><title>Genome Assessment Report</title>{style}</head><body>"]
    html.append("<div class='container'>")
    html.append("<h1>Genome Assembly Assessment Report</h1>")
    
    # --- SECTION 1: BUSCO ---
    html.append("<h2>1. Biological Completeness (BUSCO)</h2>")
    html.append("<table><thead><tr><th>Sample</th><th>Chart</th><th>Complete (C)</th><th>Single (S)</th><th>Duplicated (D)</th><th>Fragmented (F)</th><th>Missing (M)</th></tr></thead><tbody>")
    
    for _, row in busco_df.iterrows():
        # Membuat Stacked Bar sederhana
        bar = f"""
        <div class="bar-container">
            <div class="bar-seg c-s" style="width: {row['Single']}%;" title="Single: {row['Single']}%">{row['Single']}%</div>
            <div class="bar-seg c-d" style="width: {row['Duplicated']}%;" title="Duplicated: {row['Duplicated']}%"></div>
            <div class="bar-seg frag" style="width: {row['Fragmented']}%;" title="Fragmented: {row['Fragmented']}%"></div>
            <div class="bar-seg miss" style="width: {row['Missing']}%;" title="Missing: {row['Missing']}%"></div>
        </div>
        """
        html.append(f"<tr><td>{row['Sample']}</td><td width='40%'>{bar}</td><td>{row['Complete']}%</td><td>{row['Single']}%</td><td>{row['Duplicated']}%</td><td>{row['Fragmented']}%</td><td>{row['Missing']}%</td></tr>")
    html.append("</tbody></table>")
    
    # --- SECTION 2: QUAST ---
    html.append("<h2>2. Assembly Statistics (QUAST)</h2>")
    # Konversi DataFrame QUAST ke HTML Table
    # Kita pilih kolom penting saja jika terlalu banyak
    cols_priority = ['Sample', '# contigs', 'Total length', 'N50', 'L50', 'GC (%)']
    # Filter kolom yang ada saja
    existing_cols = [c for c in cols_priority if c in quast_df.columns]
    # Tambahkan sisa kolom lain di belakang
    other_cols = [c for c in quast_df.columns if c not in cols_priority]
    
    final_cols = existing_cols + other_cols
    html_table = quast_df[final_cols].to_html(index=False, border=0, classes="quast-table")
    html.append(html_table.replace('class="dataframe"', '')) # Clean up pandas default class
    
    html.append("</div></body></html>")
    
    with open(output_file, 'w') as f:
        f.write("\n".join(html))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--quast', nargs='+', required=True, help='List of QUAST report.tsv files')
    parser.add_argument('--busco', nargs='+', required=True, help='List of BUSCO short_summary.txt files')
    parser.add_argument('--samples', nargs='+', required=True, help='List of sample names corresponding to files')
    parser.add_argument('--output', required=True, help='Output HTML file')
    args = parser.parse_args()

    # Process Data
    quast_data = []
    busco_data = []
    
    for q_file, b_file, sample in zip(args.quast, args.busco, args.samples):
        q = parse_quast(q_file, sample)
        b = parse_busco(b_file, sample)
        if q: quast_data.append(q)
        if b: busco_data.append(b)
        
    df_quast = pd.DataFrame(quast_data)
    df_busco = pd.DataFrame(busco_data)
    
    # Generate Report
    generate_html(df_quast, df_busco, args.output)

if __name__ == "__main__":
    main()