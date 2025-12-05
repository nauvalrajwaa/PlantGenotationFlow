rule assembly_hifiasm:
    input:
        reads = lambda wildcards: samples_df.loc[wildcards.sample, "reads_path"]
    output:
        gfa = "results/assembly/{sample}/{sample}.bp.p_ctg.gfa",
        fasta = "results/assembly/{sample}/{sample}.assembly.fa"
    threads: config["threads"]["assembly"]
    # MENGGUNAKAN FILE YAML
    conda: "../envs/assembly.yaml" 
    log: "logs/assembly/{sample}.log"
    shell:
        """
        hifiasm -o results/assembly/{wildcards.sample}/{wildcards.sample} -t {threads} {input.reads} 2> {log}
        awk '/^S/{{print ">"$2;print $3}}' {output.gfa} > {output.fasta}
        """