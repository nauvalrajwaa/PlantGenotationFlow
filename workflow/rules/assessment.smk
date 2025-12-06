# -----------------------------------------------------------------------------
# 1. QUAST QC
# -----------------------------------------------------------------------------
rule quast_qc:
    input:
        assembly = "results/medaka/{sample}/consensus.fasta",
        ref      = config["refs"]["genome"]
    output:
        report_html = "results/qc/quast/{sample}/report.html",
        # TAMBAHAN: Kita butuh TSV untuk dibaca script python
        report_tsv  = "results/qc/quast/{sample}/report.tsv"
    conda:
        "../envs/assessment.yaml"
    params:
        outdir = directory("results/qc/quast/{sample}")
    threads: 8
    shell:
        """
        quast.py {input.assembly} \
                 -r {input.ref} \
                 -o {params.outdir} \
                 --threads {threads} \
                 --large \
                 --k-mer-stats
        """

# -----------------------------------------------------------------------------
# 2. BUSCO QC
# -----------------------------------------------------------------------------
rule busco_qc:
    input:
        "results/medaka/{sample}/consensus.fasta"
    output:
        summary = "results/qc/busco/{sample}/short_summary.txt",
        outdir  = directory("results/qc/busco/{sample}")
    conda:
        "../envs/assessment.yaml"
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
              --out_path results/qc/busco/ \
              -m {params.mode} \
              -c {threads} \
              --force
        
        find {output.outdir} -name "short_summary*.txt" -exec cp {{}} {output.summary} \;
        """

# -----------------------------------------------------------------------------
# 3. FINAL AGGREGATE REPORT (BARU)
# -----------------------------------------------------------------------------
rule generate_assessment_report:
    input:
        # Mengumpulkan hasil dari SEMUA sampel
        quast_files = expand("results/qc/quast/{sample}/report.tsv", sample=samples.index),
        busco_files = expand("results/qc/busco/{sample}/short_summary.txt", sample=samples.index)
    output:
        html = "results/qc/Final_Genome_Assessment.html"
    conda:
        "../envs/assessment.yaml"
    params:
        # Mengirim daftar nama sampel ke script python
        sample_names = lambda wildcards: list(samples.index)
    script:
        # Lokasi script python yang tadi dibuat
        "../scripts/generate_assessment.py"