# QUAST: Statistik Assembly (N50, L50, Mismatches)
rule quast_qc:
    input:
        assembly = "results/medaka/{sample}/consensus.fasta",
        ref      = config["refs"]["genome"]
    output:
        report = "results/qc/quast/{sample}/report.html"
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

# BUSCO: Kelengkapan Gen (Biological Completeness)
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
        # Perhatikan huruf 'r' di bawah ini (r""")
        r"""
        rm -rf {params.outdir}
        
        busco -i {input} \
              -l {params.lineage} \
              -o {wildcards.sample} \
              --out_path results/qc/busco/ \
              -m {params.mode} \
              -c {threads} \
              --force
        
        # Syntax find di bawah ini yang menyebabkan warning jika tidak pakai raw string
        find results/qc/busco/{wildcards.sample} -name "short_summary*.txt" -exec cp {{}} {output.summary} \;
        """