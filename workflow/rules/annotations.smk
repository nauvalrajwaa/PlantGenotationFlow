# -----------------------------------------------------------------------------
# 1. LIFTOFF (Metode Utama - DNA Based)
# -----------------------------------------------------------------------------
rule liftoff_annotation:
    input:
        target    = "results/medaka/{sample}/consensus.fasta",
        ref_fasta = config["refs"]["genome"],
        ref_gff   = config["refs"]["gff"]
    output:
        gff         = "results/annotation/{sample}_liftoff.gff3",
        unmapped    = "results/annotation/{sample}_liftoff_unmapped.txt",
        # Output protein dipindah ke hasil gffread, bukan langsung dari liftoff
        polypeptide = "results/annotation/{sample}_liftoff_protein.fasta"
    conda:
        "../envs/annotation.yaml"
    threads: 32
    params:
        # Parameter sesuai dokumentasi user:
        # -a 0.85: coverage threshold
        # -s 0.85: sequence identity threshold
        # -copies: cari copy number extra (bagus untuk tanaman)
        extra_args = "-a 0.85 -s 0.85 -copies" 
    shell:
        """
        # 1. Jalankan Liftoff
        # Note: Flag -f dihapus karena itu untuk filtering tipe fitur, bukan output file
        liftoff -g {input.ref_gff} \
                -o {output.gff} \
                -u {output.unmapped} \
                {params.extra_args} \
                -p {threads} \
                {input.target} {input.ref_fasta}

        # 2. Generate Protein Fasta menggunakan gffread
        # Liftoff cuma bikin GFF, kita butuh gffread untuk ambil sequence proteinnya
        gffread {output.gff} \
                -g {input.target} \
                -y {output.polypeptide}
        """

# -----------------------------------------------------------------------------
# 2. GALBA (Metode Cadangan - Protein Based) via DOCKER
# -----------------------------------------------------------------------------
rule galba_annotation:
    input:
        target   = "results/medaka/{sample}/consensus.fasta",
        ref_prot = config["refs"]["protein"]
    output:
        gff = "results/annotation/{sample}_galba.gff3"
    # Menggunakan Container sesuai instruksi
    container: 
        "docker://katharinahoff/galba-notebook:latest"
    threads: 32
    shell:
        """
        # GALBA butuh writable config directory.
        # Kita buat folder config sementara di dalam results agar tidak permission denied.
        
        export AUGUSTUS_CONFIG_PATH="results/annotation/augustus_config_{wildcards.sample}"
        mkdir -p $AUGUSTUS_CONFIG_PATH
        
        # Copy config default container ke folder lokal kita (sesuai saran dokumentasi)
        cp -r /usr/share/augustus/config/* $AUGUSTUS_CONFIG_PATH/
        
        # Jalankan GALBA
        # galba.pl adalah executable dalam container tersebut
        galba.pl --genome={input.target} \
                 --prot_seq={input.ref_prot} \
                 --threads {threads} \
                 --gff3={output.gff}
                 
        # Bersihkan folder config sementara setelah selesai
        rm -rf $AUGUSTUS_CONFIG_PATH
        """

# -----------------------------------------------------------------------------
# 3. Summary Stats
# -----------------------------------------------------------------------------
rule annotation_stats:
    input:
        liftoff = "results/annotation/{sample}_liftoff.gff3",
        galba   = "results/annotation/{sample}_galba.gff3"
    output:
        summary = "results/annotation/{sample}_stats.txt"
    shell:
        """
        echo "Annotation Statistics for {wildcards.sample}" > {output.summary}
        echo "-------------------------------------------" >> {output.summary}
        
        echo "[LIFTOFF] Gene Count:" >> {output.summary}
        # Menghitung fitur 'gene' di kolom ke-3 GFF
        awk '$3 == "gene"' {input.liftoff} | wc -l >> {output.summary}
        
        echo "" >> {output.summary}
        
        echo "[GALBA] Gene Count:" >> {output.summary}
        # Galba kadang menggunakan gene atau mRNA tergantung versi, kita hitung gene
        awk '$3 == "gene"' {input.galba} | wc -l >> {output.summary}
        """