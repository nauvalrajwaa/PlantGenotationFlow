# -----------------------------------------------------------------------------
# 1. LIFTOFF (Metode Utama - DNA Based)
# -----------------------------------------------------------------------------
rule liftoff_annotation:
    input:
        # Mengambil input dari hasil bersih Tiara
        target    = "results/final_genome/{sample}_final_clean.fasta",
        ref_fasta = config["refs"]["genome"],
        ref_gff   = config["refs"]["gff"]
    output:
        gff         = "results/annotation/{sample}_liftoff.gff3",
        unmapped    = "results/annotation/{sample}_liftoff_unmapped.txt",
        polypeptide = "results/annotation/{sample}_liftoff_protein.fasta"
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
        # Mengambil input dari hasil bersih Tiara
        target   = "results/final_genome/{sample}_final_clean.fasta",
        ref_prot = config["refs"]["protein"]
    output:
        gff = "results/annotation/{sample}_galba.gff3"
    container:
        "docker://katharinahoff/galba-notebook:latest"
    threads: 32
    shell:
        """
        # Setup folder config sementara untuk Augustus agar writable
        export AUGUSTUS_CONFIG_PATH="results/annotation/augustus_config_{wildcards.sample}"
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
# 3. TETOOLS (Dfam RepeatMasker - Repeat Detection) via DOCKER
# -----------------------------------------------------------------------------
rule tetools_annotation:
    input:
        target = "results/final_genome/{sample}_final_clean.fasta"
    output:
        masked = "results/annotation/{sample}_tetools.fasta.masked",
        tbl    = "results/annotation/{sample}_tetools.fasta.tbl",
        out    = "results/annotation/{sample}_tetools.fasta.out"
    container:
        "docker://dfam/tetools:latest"
    threads: 8
    params:
        species = config["tetools"]["species"],
        dir     = "results/annotation"
    shell:
        """
        # Copy input untuk konsistensi output naming
        cp {input.target} {params.dir}/{wildcards.sample}_tetools.fasta
        
        # Run RepeatMasker dengan tetools
        RepeatMasker \
            -pa {threads} \
            -species "{params.species}" \
            -dir {params.dir} \
            {params.dir}/{wildcards.sample}_tetools.fasta
        
        # Cleanup temporary file
        rm {params.dir}/{wildcards.sample}_tetools.fasta
        """

# -----------------------------------------------------------------------------
# 4. Summary Stats
# -----------------------------------------------------------------------------
rule annotation_stats:
    input:
        liftoff = "results/annotation/{sample}_liftoff.gff3",
        galba   = "results/annotation/{sample}_galba.gff3",
        tetools = "results/annotation/{sample}_tetools.fasta.tbl"
    output:
        summary = "results/annotation/{sample}_stats.txt"
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
        
        echo "[TETOOLS] Repeat Summary:" >> {output.summary}
        tail -3 {input.tetools} >> {output.summary}
        """

# -----------------------------------------------------------------------------
# 5. FINAL HTML REPORT (Visualization)
# -----------------------------------------------------------------------------
rule generate_annotation_report:
    input:
        liftoff_files = expand("results/annotation/{sample}_liftoff.gff3", sample=samples.index),
        galba_files   = expand("results/annotation/{sample}_galba.gff3", sample=samples.index),
        tetools_files = expand("results/annotation/{sample}_tetools.fasta.tbl", sample=samples.index)
    output:
        html = "results/annotation/Final_Annotation_Report.html"
    conda:
        "../envs/annotation.yaml"
    params:
        sample_list = lambda wildcards, input: " ".join(samples.index)
    shell:
        """
        python workflow/scripts/generate_annotation_report.py \
            --liftoff {input.liftoff_files} \
            --galba {input.galba_files} \
            --tetools {input.tetools_files} \
            --samples {params.sample_list} \
            --output {output.html}
        """