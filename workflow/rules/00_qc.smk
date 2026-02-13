# -----------------------------------------------------------------------------
# RAW READ QUALITY CONTROL (NANOPLOT)
# -----------------------------------------------------------------------------
rule nanoplot_qc:
    input:
        get_reads
    output:
        report = "results/{sample}/qc/nanoplot/NanoPlot-report.html",
        stats  = "results/{sample}/qc/nanoplot/NanoStats.txt"
    conda:
        "../envs/qc.yaml"
    params:
        outdir = directory("results/{sample}/qc/nanoplot")
    threads: 8
    shell:
        """
        NanoPlot --fastq {input} \
                 --outdir {params.outdir} \
                 --threads {threads} \
                 --plots hex dot
        """

# -----------------------------------------------------------------------------
# OPTIONAL: READ FILTERING (FILTLONG)
# -----------------------------------------------------------------------------
# Uncomment and connect to assembly input if filtering is desired
# rule filtlong:
#     input:
#         get_reads
#     output:
#         "results/filtered_reads/{sample}.fastq.gz"
#     conda:
#         "../envs/qc.yaml"
#     params:
#         min_length = 1000,
#         keep_percent = 95
#     threads: 8
#     shell:
#         "filtlong --min_length {params.min_length} --keep_percent {params.keep_percent} {input} | gzip > {output}"
