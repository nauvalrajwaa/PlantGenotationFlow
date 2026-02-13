# -----------------------------------------------------------------------------
# 1. LIFTOFF (Metode Utama - DNA Based)
# -----------------------------------------------------------------------------
rule liftoff_annotation:
    input:
        # Mengambil input dari hasil bersih Tiara
        target    = "results/{sample}/final_genome/final_clean.fasta",
        ref_fasta = config["refs"]["genome"],
        ref_gff   = config["refs"]["gff"]
    output:
        gff         = "results/{sample}/annotation/liftoff.gff3",
        unmapped    = "results/{sample}/annotation/liftoff_unmapped.txt",
        polypeptide = "results/{sample}/annotation/liftoff_protein.fasta"
    conda:
        "../envs/annotation.yaml"
    threads: 32
    params:
        extra_args = "-a 0.85 -s 0.85 -copies"
    shell:
        """
        liftoff -g {input.ref_gff} \
                -o {output.gff} \
                -u {output.unmapped} \
                {params.extra_args} \
                -p {threads} \
                {input.target} {input.ref_fasta}

        # Generate Protein Fasta menggunakan gffread
        gffread {output.gff} \
                -g {input.target} \
                -y {output.polypeptide}
        """

# -----------------------------------------------------------------------------
# 2. GALBA (Metode Cadangan - Protein Based) via DOCKER
# -----------------------------------------------------------------------------
rule galba_annotation:
    input:
        # Menggunakan soft-masked genome dari repeat masking (EDTA atau TEtools layer2)
        # agar Augustus/GALBA dapat mengenali region repeat (best practice)
        target   = get_masked_genome,
        ref_prot = config["refs"]["protein"]
    output:
        gff = "results/{sample}/annotation/galba.gff3"
    container:
        "docker://katharinahoff/galba-notebook:latest"
    threads: 32
    shell:
        """
        # Setup folder config sementara untuk Augustus agar writable
        export AUGUSTUS_CONFIG_PATH="results/{wildcards.sample}/annotation/augustus_config"
        mkdir -p $AUGUSTUS_CONFIG_PATH
        cp -r /usr/share/augustus/config/* $AUGUSTUS_CONFIG_PATH/
        
        # Jalankan Galba
        galba.pl --genome={input.target} \
                 --prot_seq={input.ref_prot} \
                 --threads {threads} \
                 --gff3={output.gff}
                 
        # Cleanup
        rm -rf $AUGUSTUS_CONFIG_PATH
        """

# -----------------------------------------------------------------------------
# 3. Summary Stats
# -----------------------------------------------------------------------------

# Helper: build annotation_stats inputs based on annotation method
def get_annotation_stats_inputs(wildcards):
    method = config.get("annotation", {}).get("method", "both")
    inputs = {"repeat_summary": get_repeat_summary(wildcards)}
    if method in ("liftoff", "both"):
        inputs["liftoff"] = f"results/{wildcards.sample}/annotation/liftoff.gff3"
    if method in ("galba", "both"):
        inputs["galba"] = f"results/{wildcards.sample}/annotation/galba.gff3"
    return inputs

rule annotation_stats:
    input:
        unpack(get_annotation_stats_inputs)
    output:
        summary = "results/{sample}/annotation/stats.txt"
    params:
        repeat_method     = config.get("repeats", {}).get("method", "edta"),
        annotation_method = config.get("annotation", {}).get("method", "both")
    shell:
        """
        echo "Annotation Statistics for {wildcards.sample}" > {output.summary}
        echo "-------------------------------------------" >> {output.summary}
        echo "Annotation method: {params.annotation_method}" >> {output.summary}
        echo "" >> {output.summary}

        if [ "{params.annotation_method}" = "liftoff" ] || [ "{params.annotation_method}" = "both" ]; then
            echo "[LIFTOFF] Gene Count:" >> {output.summary}
            awk '$3 == "gene"' {input.liftoff} | wc -l >> {output.summary}
            echo "" >> {output.summary}
        fi

        if [ "{params.annotation_method}" = "galba" ] || [ "{params.annotation_method}" = "both" ]; then
            echo "[GALBA] Gene Count:" >> {output.summary}
            awk '$3 == "gene"' {input.galba} | wc -l >> {output.summary}
            echo "" >> {output.summary}
        fi

        echo "[REPEAT MASKING] Method: {params.repeat_method}" >> {output.summary}
        cat {input.repeat_summary} >> {output.summary}
        """

# (Report generation is now handled by the unified generate_pipeline_report rule
#  in 02_assessment.smk → results/reports/index.html)