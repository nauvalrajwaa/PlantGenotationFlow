# -----------------------------------------------------------------------------
# REPEAT MASKING WITH EDTA (Singularity/Docker version)
# -----------------------------------------------------------------------------

rule edta_masking:
    input:
        # UPDATE: Input dari Tiara Final
        genome = "results/final_genome/{sample}_final_clean.fasta",
        cds    = config["refs"]["cds"] if "cds" in config["refs"] else [] 
    output:
        masked = "results/repeats/{sample}/genome.fasta.mod.MAKER.masked",
        # Output tambahan (Library TE)
        te_lib = "results/repeats/{sample}/genome.fasta.mod.EDTA.TElib.fa",
        # Output summary stats
        summary= "results/repeats/{sample}/genome.fasta.mod.EDTA.TEanno.sum"
    
    # 1. Gunakan Image Resmi dari BioContainers (sesuai dokumentasi)
    container:
        "docker://quay.io/biocontainers/edta:2.2.0--hdfd78af_1"
        
    params:
        species = config["repeats"]["species"], # Contoh: Rice, Maize, atau others
        outdir  = directory("results/repeats/{sample}"),
        
        # CDS Flag logic: jika file CDS ada di config, tambahkan flagnya
        cds_arg = lambda wildcards, input: f"--cds reference_cds.fasta" if input.cds else ""
        
    threads: 32
    shell:
        """
        # --- PERSIAPAN LOKASI KERJA ---
        # EDTA sangat sensitif terhadap path. Kita harus copy file ke folder kerja
        # dan menjalankannya dari 'current directory' agar tidak error.
        
        mkdir -p {params.outdir}
        
        # Copy genome assembly ke folder output dengan nama sederhana
        cp {input.genome} {params.outdir}/genome.fasta
        
        # (Opsional) Copy CDS referensi jika ada
        if [ ! -z "{input.cds}" ]; then
            cp {input.cds} {params.outdir}/reference_cds.fasta
        fi
        
        # Pindah ke directory tersebut
        cd {params.outdir}
        
        # --- EKSEKUSI EDTA ---
        # --overwrite 1: Timpa jika ada sisa run gagal
        # --sensitive 1: Pakai RepeatModeler (Wajib untuk akurasi tinggi)
        # --anno 1: Lakukan whole genome annotation & masking
        
        EDTA.pl --genome genome.fasta \
                --species {params.species} \
                {params.cds_arg} \
                --step all \
                --sensitive 1 \
                --anno 1 \
                --threads {threads} \
                --overwrite 1
        
        # Tidak perlu move output, karena kita sudah bekerja di folder {params.outdir}
        # Output file otomatis akan bernama: genome.fasta.mod.MAKER.masked, dll.
        """