# -----------------------------------------------------------------------------
# ASSEMBLY RULES
# -----------------------------------------------------------------------------

# Helper function untuk menentukan input assembly berdasarkan config
def get_raw_assembly(wildcards):
    method = config["assembly"]["method"]
    if method == "flye":
        return f"results/assembly/flye/{wildcards.sample}/assembly.fasta"
    elif method == "hifiasm":
        return f"results/assembly/hifiasm/{wildcards.sample}/assembly.fasta"
    else:
        raise ValueError(f"Unknown assembly method in config: {method}")

# 1. FLYE ASSEMBLER
rule flye_assembly:
    input:
        get_reads
    output:
        fasta = "results/assembly/flye/{sample}/assembly.fasta",
        info  = "results/assembly/flye/{sample}/assembly_info.txt"
    conda:
        "../envs/assembly.yaml"
    params:
        mode   = config["assembly"]["flye"]["mode"],
        g_size = config["assembly"]["flye"]["genome_size"],
        outdir = directory("results/assembly/flye/{sample}")
    threads: 32
    shell:
        """
        flye {params.mode} {input} \
             --genome-size {params.g_size} \
             --out-dir {params.outdir} \
             --threads {threads} \
             --iterations 1
             
        # Rename output flye default (assembly.fasta) is handled by flye --out-dir structure usually,
        # but flye outputs 'assembly.fasta' inside the dir.
        """

# 2. HIFIASM ASSEMBLER
rule hifiasm_assembly:
    input:
        get_reads
    output:
        primary_gfa = "results/assembly/hifiasm/{sample}/{sample}.asm.bp.p_ctg.gfa",
        fasta       = "results/assembly/hifiasm/{sample}/assembly.fasta"
    conda:
        "../envs/assembly.yaml"
    params:
        extra_args = config["assembly"]["hifiasm"]["extra_args"],
        prefix     = "results/assembly/hifiasm/{sample}/{sample}.asm"
    threads: 32
    shell:
        """
        # Run Hifiasm
        hifiasm -o {params.prefix} \
                -t {threads} \
                {params.extra_args} \
                {input}
        
        # Convert GFA to FASTA (Primary Contigs)
        awk '/^S/{{print ">"$2;print $3}}' {output.primary_gfa} > {output.fasta}
        """

# 3. SELECT ASSEMBLY
# Rule ini "memilih" file mana yang akan digunakan sebagai "results/assembly/{sample}/assembly.fasta"
# agar rule Medaka tidak perlu berubah banyak.
rule select_assembly:
    input:
        get_raw_assembly
    output:
        "results/assembly/{sample}/assembly.fasta"
    shell:
        """
        cp {input} {output}
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