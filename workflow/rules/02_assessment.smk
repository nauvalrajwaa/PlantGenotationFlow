# -----------------------------------------------------------------------------
# 1. QUAST QC (Preliminary vs Final)
# -----------------------------------------------------------------------------
rule quast_qc:
    input:
        assembly = "results/{sample}/medaka/consensus.fasta",
        final    = "results/{sample}/final_genome/final_clean.fasta",
        ref      = config["refs"]["genome"]
    output:
        report_html = "results/{sample}/qc/quast/report.html",
        report_tsv  = "results/{sample}/qc/quast/report.tsv"
    conda:
        "../envs/quast.yaml"
    params:
        outdir = directory("results/{sample}/qc/quast")
    threads: 8
    shell:
        """
        # Run QUAST comparing Draft (Medaka) and Final (Cleaned)
        quast.py {input.assembly} {input.final} \
                 -l "Draft_Assembly, Final_Cleaned" \
                 -r {input.ref} \
                 -o {params.outdir} \
                 --threads {threads} \
                 --large \
                 --k-mer-stats
        """

# -----------------------------------------------------------------------------
# 2. BUSCO QC (Final Genome)
# -----------------------------------------------------------------------------
rule busco_qc:
    input:
        "results/{sample}/final_genome/final_clean.fasta"
    output:
        summary = "results/{sample}/qc/busco/short_summary.txt",
        outdir  = directory("results/{sample}/qc/busco")
    conda:
        "../envs/busco.yaml"
    params:
        lineage = config["busco"]["lineage"],
        mode = "genome"
    threads: 16
    shell:
        r"""
        rm -rf {output.outdir}
        
        busco -i {input} \
              -l {params.lineage} \
              -o {wildcards.sample} \
              --out_path results/{wildcards.sample}/qc/busco_tmp/ \
              -m {params.mode} \
              -c {threads} \
              --force
        
        # Move busco output to expected location
        mv results/{wildcards.sample}/qc/busco_tmp/{wildcards.sample} {output.outdir}
        rm -rf results/{wildcards.sample}/qc/busco_tmp
        mv {output.outdir}/short_summary.*.txt {output.summary}
        """

# -----------------------------------------------------------------------------
# 3. PER-SAMPLE STANDALONE REPORT
# -----------------------------------------------------------------------------
# Collects all report files into results/{sample}/report/ and generates
# a standalone index.html that displays every pipeline section.
# -----------------------------------------------------------------------------

def get_sample_report_inputs(wildcards):
    """Return all tracked inputs needed for the per-sample report."""
    inputs = {
        "nanoplot_stats":   f"results/{wildcards.sample}/qc/nanoplot/NanoStats.txt",
        "nanoplot_report":  f"results/{wildcards.sample}/qc/nanoplot/NanoPlot-report.html",
        "quast_report":     f"results/{wildcards.sample}/qc/quast/report.html",
        "quast_tsv":        f"results/{wildcards.sample}/qc/quast/report.tsv",
        "busco_summary":    f"results/{wildcards.sample}/qc/busco/short_summary.txt",
        "rejected_ids":     f"results/{wildcards.sample}/final_genome/rejected_ids.txt",
        "annotation_stats": f"results/{wildcards.sample}/annotation/stats.txt",
    }
    method = config.get("repeats", {}).get("method", "edta")
    if method == "tetools":
        inputs["layer1_tbl"] = f"results/{wildcards.sample}/repeats/layer1/genome.fa.tbl"
        inputs["layer2_tbl"] = f"results/{wildcards.sample}/repeats/layer2/genome.masked.fa.tbl"
    else:
        inputs["edta_summary"] = f"results/{wildcards.sample}/repeats/genome.fasta.mod.EDTA.TEanno.sum"
    return inputs


rule collect_and_generate_report:
    input:
        unpack(get_sample_report_inputs)
    output:
        html = "results/{sample}/report/index.html"
    params:
        report_dir        = lambda wildcards: f"results/{wildcards.sample}/report",
        repeat_method     = config.get("repeats", {}).get("method", "edta"),
        annotation_method = config.get("annotation", {}).get("method", "both")
    shell:
        """
        REPORT_DIR="{params.report_dir}"

        # Create report subdirectories
        mkdir -p "$REPORT_DIR/nanoplot" \
                 "$REPORT_DIR/quast" \
                 "$REPORT_DIR/busco" \
                 "$REPORT_DIR/decontamination" \
                 "$REPORT_DIR/repeats" \
                 "$REPORT_DIR/annotation"

        # --- NanoPlot (copy entire directory for HTML plot dependencies) ---
        cp -r results/{wildcards.sample}/qc/nanoplot/* "$REPORT_DIR/nanoplot/" 2>/dev/null || true

        # --- QUAST (copy entire directory for Icarus viewer dependencies) ---
        cp -r results/{wildcards.sample}/qc/quast/* "$REPORT_DIR/quast/" 2>/dev/null || true

        # --- BUSCO ---
        cp {input.busco_summary} "$REPORT_DIR/busco/"

        # --- Decontamination ---
        cp results/{wildcards.sample}/decontamination/tiara/log_classification.txt \
           "$REPORT_DIR/decontamination/" 2>/dev/null || true
        cp {input.rejected_ids} "$REPORT_DIR/decontamination/"

        # --- Repeats ---
        if [ "{params.repeat_method}" = "tetools" ]; then
            cp results/{wildcards.sample}/repeats/layer1/genome.fa.tbl \
               "$REPORT_DIR/repeats/" 2>/dev/null || true
            cp results/{wildcards.sample}/repeats/layer2/genome.masked.fa.tbl \
               "$REPORT_DIR/repeats/" 2>/dev/null || true
            # RepeatModeler log (best-effort: file is produced by RepeatModeler
            # but not a formal Snakemake output to avoid costly re-runs)
            cp results/{wildcards.sample}/repeats/repeatmodeler/{wildcards.sample}-rmod.log \
               "$REPORT_DIR/repeats/repeatmodeler.log" 2>/dev/null || true
        else
            cp results/{wildcards.sample}/repeats/genome.fasta.mod.EDTA.TEanno.sum \
               "$REPORT_DIR/repeats/edta_summary.txt" 2>/dev/null || true
        fi

        # --- Annotation ---
        cp {input.annotation_stats} "$REPORT_DIR/annotation/"

        # --- Generate standalone HTML report ---
        python workflow/scripts/generate_pipeline_report.py \
            --sample {wildcards.sample} \
            --report-dir "$REPORT_DIR" \
            --repeat-method {params.repeat_method} \
            --annotation-method {params.annotation_method} \
            --output {output.html}
        """