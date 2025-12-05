rule liftoff_annotation:
    input:
        target = "results/medaka/{sample}/consensus.fasta",
        ref_fasta = config["refs"]["genome"],
        ref_gff = config["refs"]["gff"]
    output:
        gff = "results/annotation/{sample}.liftoff.gff3",
        unmapped = "results/annotation/{sample}_unmapped.txt",
        polypeptide = "results/annotation/{sample}_protein.fasta"
    conda:
        "../envs/annotation.yaml"
    threads: 32
    shell:
        """
        liftoff -g {input.ref_gff} \
                -o {output.gff} \
                -u {output.unmapped} \
                -a 0.85 -s 0.85 \
                -p {threads} \
                -f {output.polypeptide} \
                {input.target} {input.ref_fasta}
        """