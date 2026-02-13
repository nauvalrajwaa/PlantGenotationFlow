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
# 3. COMPREHENSIVE PIPELINE REPORT (indexed HTML)
# -----------------------------------------------------------------------------
def get_report_repeat_inputs():
    """Return the correct repeat summary inputs for the pipeline report based on config."""
    method = config.get("repeats", {}).get("method", "edta")
    if method == "tetools":
        return {
            "edta_summaries": [],
            "layer2_tbls": expand("results/{sample}/repeats/layer2/genome.masked.fa.tbl", sample=samples.index),
        }
    else:  # edta
        return {
            "edta_summaries": expand("results/{sample}/repeats/genome.fasta.mod.EDTA.TEanno.sum", sample=samples.index),
            "layer2_tbls": [],
        }

def get_report_annotation_inputs():
    """Return the correct annotation GFF inputs based on config."""
    method = config.get("annotation", {}).get("method", "both")
    result = {"liftoff_gffs": [], "galba_gffs": []}
    if method in ("liftoff", "both"):
        result["liftoff_gffs"] = expand("results/{sample}/annotation/liftoff.gff3", sample=samples.index)
    if method in ("galba", "both"):
        result["galba_gffs"] = expand("results/{sample}/annotation/galba.gff3", sample=samples.index)
    return result

_report_repeat_inputs = get_report_repeat_inputs()
_report_annotation_inputs = get_report_annotation_inputs()

rule generate_pipeline_report:
    input:
        nanoplot_stats   = expand("results/{sample}/qc/nanoplot/NanoStats.txt", sample=samples.index),
        quast_tsvs       = expand("results/{sample}/qc/quast/report.tsv", sample=samples.index),
        busco_summaries  = expand("results/{sample}/qc/busco/short_summary.txt", sample=samples.index),
        rejected_ids     = expand("results/{sample}/final_genome/rejected_ids.txt", sample=samples.index),
        edta_summaries   = _report_repeat_inputs["edta_summaries"],
        layer2_tbls      = _report_repeat_inputs["layer2_tbls"],
        liftoff_gffs     = _report_annotation_inputs["liftoff_gffs"],
        galba_gffs       = _report_annotation_inputs["galba_gffs"],
        annotation_stats = expand("results/{sample}/annotation/stats.txt", sample=samples.index),
    output:
        html = "results/reports/index.html"
    conda:
        "../envs/quast.yaml"
    params:
        sample_names      = lambda wildcards: list(samples.index),
        repeat_method     = config.get("repeats", {}).get("method", "edta"),
        annotation_method = config.get("annotation", {}).get("method", "both")
    script:
        "../scripts/generate_pipeline_report.py"