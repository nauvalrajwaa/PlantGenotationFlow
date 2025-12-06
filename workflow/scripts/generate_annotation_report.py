import argparse
import pandas as pd
import matplotlib.pyplot as plt
import io
import base64
import os

def parse_gff(gff_file):
    """Membaca GFF3 dan mengambil statistik gen."""
    gene_lengths = []
    gene_count = 0
    mrna_count = 0
    
    try:
        with open(gff_file, 'r') as f:
            for line in f:
                if line.startswith("#"): continue
                parts = line.strip().split('\t')
                if len(parts) < 9: continue
                
                feature_type = parts[2]
                start = int(parts[3])
                end = int(parts[4])
                length = end - start + 1
                
                if feature_type == 'gene':
                    gene_count += 1
                    gene_lengths.append(length)
                elif feature_type in ['mRNA', 'transcript']:
                    mrna_count += 1
                    
        return {
            'gene_count': gene_count,
            'mrna_count': mrna_count,
            'lengths': gene_lengths,
            'avg_len': sum(gene_lengths)/len(gene_lengths) if gene_lengths else 0
        }
    except Exception as e:
        print(f"Error parsing {gff_file}: {e}")
        return None

def plot_to_base64(plt_obj):
    """Mengubah plot matplotlib menjadi string base64 untuk HTML."""
    buf = io.BytesIO()
    plt_obj.savefig(buf, format='png', bbox_inches='tight')
    buf.seek(0)
    return base64.b64encode(buf.read()).decode('utf-8')

def generate_report(liftoff_files, galba_files, samples, output_html):
    data_summary = []
    
    # 1. Parse Data
    all_liftoff_lengths = []
    all_galba_lengths = []
    
    for l_file, g_file, sample in zip(liftoff_files, galba_files, samples):
        l_stats = parse_gff(l_file)
        g_stats = parse_gff(g_file)
        
        if l_stats:
            data_summary.append({
                'Sample': sample, 'Method': 'Liftoff', 
                'Genes': l_stats['gene_count'], 'Avg Length': int(l_stats['avg_len'])
            })
            all_liftoff_lengths.extend(l_stats['lengths'])
            
        if g_stats:
            data_summary.append({
                'Sample': sample, 'Method': 'Galba', 
                'Genes': g_stats['gene_count'], 'Avg Length': int(g_stats['avg_len'])
            })
            all_galba_lengths.extend(g_stats['lengths'])

    df = pd.DataFrame(data_summary)

    # 2. Generate Plots
    
    # Plot A: Comparison Bar Chart
    fig1, ax1 = plt.subplots(figsize=(10, 6))
    if not df.empty:
        pivot_df = df.pivot(index='Sample', columns='Method', values='Genes')
        pivot_df.plot(kind='bar', ax=ax1, color=['#2ca02c', '#1f77b4'])
        ax1.set_title("Gene Count Comparison: Liftoff vs Galba")
        ax1.set_ylabel("Number of Predicted Genes")
        plt.xticks(rotation=45)
    img_bar = plot_to_base64(plt)
    plt.close()

    # Plot B: Gene Length Distribution (Histogram)
    fig2, ax2 = plt.subplots(figsize=(10, 6))
    ax2.hist(all_liftoff_lengths, bins=50, range=(0, 10000), alpha=0.5, label='Liftoff', color='#2ca02c')
    ax2.hist(all_galba_lengths, bins=50, range=(0, 10000), alpha=0.5, label='Galba', color='#1f77b4')
    ax2.set_title("Gene Length Distribution (0 - 10kb)")
    ax2.set_xlabel("Gene Length (bp)")
    ax2.set_ylabel("Frequency")
    ax2.legend()
    img_hist = plot_to_base64(plt)
    plt.close()

    # 3. Generate HTML
    html_content = f"""
    <html>
    <head>
        <title>Final Annotation Report</title>
        <style>
            body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f9f9f9; }}
            .container {{ max_width: 1000px; margin: auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 0 15px rgba(0,0,0,0.1); }}
            h1 {{ color: #2c3e50; text-align: center; }}
            h2 {{ color: #34495e; border-bottom: 2px solid #eee; padding-bottom: 10px; margin-top: 30px; }}
            table {{ width: 100%; border-collapse: collapse; margin-top: 15px; }}
            th, td {{ padding: 12px; border: 1px solid #ddd; text-align: left; }}
            th {{ background-color: #3498db; color: white; }}
            tr:nth-child(even) {{ background-color: #f2f2f2; }}
            .plot-box {{ text-align: center; margin-top: 20px; }}
            img {{ max-width: 100%; height: auto; border: 1px solid #ddd; padding: 5px; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Annotation Pipeline Report</h1>
            <p>Summary of structural annotation results from Liftoff (DNA-based) and Galba (Protein-based).</p>
            
            <h2>1. Statistics Summary</h2>
            {df.to_html(index=False, border=0, classes="stats-table")}
            
            <h2>2. Gene Count Comparison</h2>
            <div class="plot-box">
                <img src="data:image/png;base64,{img_bar}" alt="Bar Chart">
                <p><i>Comparison of total gene models found by each tool.</i></p>
            </div>

            <h2>3. Gene Length Distribution</h2>
            <div class="plot-box">
                <img src="data:image/png;base64,{img_hist}" alt="Histogram">
                <p><i>Distribution of gene lengths (capped at 10kb for visibility). Overlapping areas show consensus.</i></p>
            </div>
        </div>
    </body>
    </html>
    """

    with open(output_html, 'w') as f:
        f.write(html_content)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--liftoff', nargs='+', required=True)
    parser.add_argument('--galba', nargs='+', required=True)
    parser.add_argument('--samples', nargs='+', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    
    generate_report(args.liftoff, args.galba, args.samples, args.output)