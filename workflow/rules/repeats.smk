rule edta_masking:
    input:
        genome = "results/medaka/{sample}/consensus.fasta"
    output:
        # EDTA outputnya ada di folder yang sama dengan nama file input
        masked = "results/repeats/{sample}/consensus.fasta.mod.MAKER.masked",
        te_lib = "results/repeats/{sample}/consensus.fasta.mod.EDTA.TElib.fa"
    conda:
        "../envs/repeats.yaml" 
    # Jika pakai singularity, uncomment baris bawah dan hapus 'conda':
    # container: "docker://hopedestruction/edta:latest"
    params:
        # Spesies: Rice, Maize, atau Others. PENTING untuk akurasi.
        species = "Rice", 
        outdir = directory("results/repeats/{sample}")
    threads: 32
    shell:
        """
        # 1. Buat folder output dan copy genome ke sana 
        # (EDTA suka error kalau output dir beda level)
        mkdir -p {params.outdir}
        cp {input.genome} {params.outdir}/genome.fasta
        
        # 2. Masuk ke folder agar output EDTA terkumpul rapi
        cd {params.outdir}
        
        # 3. Jalankan EDTA
        # --sensitive 1: Pake RepeatModeler (lama tapi akurat)
        # --anno 1: Langsung lakukan masking (bikin file .masked)
        EDTA.pl --genome genome.fasta \
                --species {params.species} \
                --step all \
                --sensitive 1 \
                --anno 1 \
                --threads {threads}
        
        # 4. Rename output agar sesuai output rule Snakemake
        # EDTA output pattern: genome.fasta.mod.MAKER.masked
        # Kita tidak perlu rename jika di snakefile outputnya sudah match pattern EDTA,
        # tapi pastikan path-nya benar.
        
        # (Opsional) Hapus file intermediate besar jika storage terbatas
        # rm genome.fasta
        """