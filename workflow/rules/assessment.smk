# QUAST: Statistik Assembly (N50, L50, Mismatches)
rule quast_qc:
    input:
        assembly = "results/medaka/{sample}/consensus.fasta",
        ref      = config["refs"]["genome"] # Opsional, tapi sangat bagus jika ada
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
        """
        # Hapus folder output jika ada (BUSCO error jika folder exist)
        rm -rf {params.outdir}
        
        busco -i {input} \
              -l {params.lineage} \
              -o {wildcards.sample} \
              --out_path results/qc/busco/ \
              -m {params.mode} \
              -c {threads} \
              --force
        
        # BUSCO output path agak tricky, kita pastikan snakemake detect file output
        # Biasanya: results/qc/busco/{sample}/short_summary.specific.{lineage}.{sample}.txt
        # Kita rename ke nama standar output yang diminta rule
        find results/qc/busco/{wildcards.sample} -name "short_summary*.txt" -exec cp {{}} {output.summary} \;
        """