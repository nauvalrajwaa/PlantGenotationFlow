# -----------------------------------------------------------------------------
# 1. QUAST QC (Preliminary vs Final)
# -----------------------------------------------------------------------------
rule quast_qc:
    input:
        assembly = "results/medaka/{sample}/consensus.fasta",
        final    = "results/final_genome/{sample}_final_clean.fasta",
        ref      = config["refs"]["genome"]
    output:
        report_html = "results/qc/quast/{sample}/report.html",
        report_tsv  = "results/qc/quast/{sample}/report.tsv"
    conda:
        "../envs/quast.yaml"
    params:
        outdir = directory("results/qc/quast/{sample}")
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
        "results/final_genome/{sample}_final_clean.fasta"
    output:
        summary = "results/qc/busco/{sample}/short_summary.txt",
        outdir  = directory("results/qc/busco/{sample}")
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
              --out_path results/qc/busco/ \
              -m {params.mode} \
              -c {threads} \
              --force
        
        # Rename default busco output dir to match expected output
        mv results/qc/busco/{wildcards.sample} {output.outdir}
        mv {output.outdir}/short_summary.*.txt {output.summary}
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
    # Menggunakan env quast saja karena sudah ada pandas
    conda:
        "../envs/quast.yaml"
    params:
        # Mengirim daftar nama sampel ke script python
        sample_names = lambda wildcards: list(samples.index)
    script:
        # Lokasi script python yang tadi dibuat
        "../scripts/generate_assessment.py"