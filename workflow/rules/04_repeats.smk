# -----------------------------------------------------------------------------
# REPEAT MASKING WITH EDTA (Singularity/Docker version)
# -----------------------------------------------------------------------------

rule edta_masking:
    input:
        # Input Genome dari Tiara/Cleaning
        genome = "results/final_genome/{sample}_final_clean.fasta",
        
        # CDS (Opsional dari config)
        cds    = config["refs"]["cds"] if "cds" in config["refs"] else [],
        
        ### UPDATE: Input Library TE
        # Mengarah langsung ke file hasil output bash script Anda yang sudah dijalankan
        te_lib = "resources/TE_Library_Prep/final_curated_lib.fa"
    
    output:
        masked = "results/repeats/{sample}/genome.fasta.mod.MAKER.masked",
        te_lib = "results/repeats/{sample}/genome.fasta.mod.EDTA.TElib.fa",
        summary= "results/repeats/{sample}/genome.fasta.mod.EDTA.TEanno.sum"
    
    container:
        "docker://quay.io/biocontainers/edta:2.2.0--hdfd78af_1"
        
    params:
        species = config["repeats"]["species"], # Gunakan 'others'
        outdir  = directory("results/repeats/{sample}"),
        
        # Helper untuk argumen CDS
        cds_arg = lambda wildcards, input: f"--cds reference_cds.fasta" if input.cds else ""
        
    threads: 32
    
    shell:
        """
        # --- 1. PERSIAPAN LOKASI KERJA ---
        mkdir -p {params.outdir}
        
        # Copy GENOME ke folder kerja
        cp {input.genome} {params.outdir}/genome.fasta
        
        ### UPDATE: Copy Library TE ke Folder Kerja
        # Kita copy file dari resources ke dalam folder output EDTA
        # dan merenamenya menjadi 'curated_lib.fasta' agar sederhana & aman dari error path
        cp {input.te_lib} {params.outdir}/curated_lib.fasta
        
        # Copy CDS (Jika ada)
        if [ ! -z "{input.cds}" ]; then
            cp {input.cds} {params.outdir}/reference_cds.fasta
        fi
        
        # Pindah ke directory kerja (PENTING: EDTA harus dijalankan dari folder outputnya)
        cd {params.outdir}
        
        # --- 2. EKSEKUSI EDTA ---
        # Flag --curatedlib ditambahkan di bawah ini
        
        EDTA.pl --genome genome.fasta \
                --species {params.species} \
                ### UPDATE: Arahkan ke file library yang baru dicopy
                --curatedlib curated_lib.fasta \
                {params.cds_arg} \
                --step all \
                --sensitive 1 \
                --anno 1 \
                --threads {threads} \
                --overwrite 1
        
        # Output otomatis tersimpan di folder ini
        """