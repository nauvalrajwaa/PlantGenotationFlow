rule flye_assembly:
    input:
        get_reads
    output:
        fasta = "results/assembly/{sample}/assembly.fasta",
        info  = "results/assembly/{sample}/assembly_info.txt"
    conda:
        "../envs/assembly.yaml"
    params:
        mode = config["assembly"]["mode"],
        g_size = config["assembly"]["genome_size"],
        outdir = directory("results/assembly/{sample}")
    threads: 32
    shell:
        """
        flye {params.mode} {input} \
             --genome-size {params.g_size} \
             --out-dir {params.outdir} \
             --threads {threads} \
             --iterations 1
        """

rule medaka_polishing:
    input:
        draft = "results/assembly/{sample}/assembly.fasta",
        reads = get_reads
    output:
        consensus = "results/medaka/{sample}/consensus.fasta"
    conda:
        "../envs/polishing.yaml"
    params:
        model = config["medaka"]["model"],
        outdir = directory("results/medaka/{sample}")
    threads: 16
    shell:
        """
        medaka_consensus -i {input.reads} \
                         -d {input.draft} \
                         -o {params.outdir} \
                         -t {threads} \
                         -m {params.model}
        """