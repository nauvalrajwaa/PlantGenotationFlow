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
        # Menggunakan soft-masked genome dari double-layer RepeatMasker
        # agar Augustus/GALBA dapat mengenali region repeat (best practice)
        target   = "results/{sample}/repeats/layer2/genome.final_masked.fa",
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
rule annotation_stats:
    input:
        liftoff    = "results/{sample}/annotation/liftoff.gff3",
        galba      = "results/{sample}/annotation/galba.gff3",
        repeat_tbl = "results/{sample}/repeats/layer2/genome.masked.fa.tbl"
    output:
        summary = "results/{sample}/annotation/stats.txt"
    shell:
        """
        echo "Annotation Statistics for {wildcards.sample}" > {output.summary}
        echo "-------------------------------------------" >> {output.summary}
        
        echo "[LIFTOFF] Gene Count:" >> {output.summary}
        awk '$3 == "gene"' {input.liftoff} | wc -l >> {output.summary}
        
        echo "" >> {output.summary}
        
        echo "[GALBA] Gene Count:" >> {output.summary}
        awk '$3 == "gene"' {input.galba} | wc -l >> {output.summary}
        
        echo "" >> {output.summary}
        
        echo "[REPEAT MASKING] Double-Layer Summary (Layer 2):" >> {output.summary}
        cat {input.repeat_tbl} >> {output.summary}
        """

# (Report generation is now handled by the unified generate_pipeline_report rule
#  in 02_assessment.smk → results/reports/index.html)