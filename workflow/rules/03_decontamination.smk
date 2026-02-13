# rules/03_decontamination.smk

# =============================================================================
# STEP 1: FCS-ADAPTOR (Technical Cleaning: Adapters & Vectors)
# =============================================================================

# 1.a. Download Resource FCS
rule fcs_setup:
    output:
        wrapper = "resources/fcs/run_fcsadaptor.sh",
        cleaner = "resources/fcs/fcs.py",
        sif     = "resources/fcs/fcs-adaptor.sif"
    shell:
        """
        mkdir -p resources/fcs
        curl -L https://github.com/ncbi/fcs/raw/main/dist/run_fcsadaptor.sh -o {output.wrapper}
        chmod 755 {output.wrapper}
        curl -L https://github.com/ncbi/fcs/raw/main/dist/fcs.py -o {output.cleaner}
        curl -L https://ftp.ncbi.nlm.nih.gov/genomes/TOOLS/FCS/releases/latest/fcs-adaptor.sif -o {output.sif}
        """

# 1.b. Screening (Mencari Adapter)
rule fcs_screen:
    input:
        assembly = "results/{sample}/medaka/consensus.fasta",
        wrapper  = "resources/fcs/run_fcsadaptor.sh",
        sif      = "resources/fcs/fcs-adaptor.sif"
    output:
        report_dir = directory("results/{sample}/decontamination/fcs/report"),
        report_txt = "results/{sample}/decontamination/fcs/report/fcs_adaptor_report.txt"
    threads: 8
    params:
        tax_group = "--euk" 
    shell:
        """
        # Gunakan path absolut untuk image agar wrapper tidak bingung
        SIF_PATH="$PWD/{input.sif}"
        
        {input.wrapper} \
            --fasta-input {input.assembly} \
            --output-dir {output.report_dir} \
            {params.tax_group} \
            --container-engine singularity \
            --image "$SIF_PATH"
        """

# 1.c. Cleaning (Membuang Adapter) - MODE FCS-GX (SESUAI DOKUMEN)
rule fcs_clean:
    input:
        assembly = "results/{sample}/medaka/consensus.fasta",
        report   = "results/{sample}/decontamination/fcs/report/fcs_adaptor_report.txt",
        cleaner  = "resources/fcs/fcs.py"
    output:
        clean_fasta  = "results/{sample}/decontamination/fcs/clean.fasta",
        contam_fasta = "results/{sample}/decontamination/fcs/contam.fasta"
    params:
        # URL resmi NCBI untuk image cleaner (GX)
        gx_url = "https://ftp.ncbi.nlm.nih.gov/genomes/TOOLS/FCS/releases/latest/fcs-gx.sif",
        gx_sif = "resources/fcs/fcs-gx.sif"
    conda:
        "../envs/fcs.yaml"
    shell:
        """
        # 1. Cek apakah image FCS-GX sudah ada? Jika belum, download dulu.
        if [ ! -f "{params.gx_sif}" ]; then
            echo "Downloading FCS-GX container (required for cleaning)..."
            curl {params.gx_url} -Lo {params.gx_sif}
        fi

        # 2. SETTING KUNCI: Paksa fcs.py pakai Singularity lewat Environment Variable
        # Ini mencegah error "permission denied" pada Docker.
        export FCS_CONTAINER_ENGINE=singularity
        export FCS_DEFAULT_IMAGE="{params.gx_sif}"

        # 3. Jalankan Cleaning
        # Kita tidak perlu lagi flag --container-engine di sini karena sudah di-export di atas.
        cat {input.assembly} | python3 {input.cleaner} clean genome \
            --action-report {input.report} \
            --output {output.clean_fasta} \
            --contam-fasta-out {output.contam_fasta}
        """

# =============================================================================
# STEP 2: TIARA (Biological Cleaning: Bacteria/Fungi Contamination)
# =============================================================================

# 2.a. Classification (Menebak Organisme Contig)
rule tiara_classification:
    input:
        fasta = "results/{sample}/decontamination/fcs/clean.fasta"
    output:
        classification = "results/{sample}/decontamination/tiara/classification.txt",
        prob           = "results/{sample}/decontamination/tiara/probabilities.txt"
    conda:
        "../envs/decon.yaml"
    threads: 8
    shell:
        """
        # 1. Jalankan Tiara
        tiara -i {input.fasta} \
              -o {output.classification} \
              --probabilities \
              -m 1000 \
              --tf mit pla \
              -t {threads}

        # 2. FAIL-SAFE LOGIC (Logika Pengaman)
        # Cari file probabilities yang mungkin digenerate dengan nama aneh
        FOUND=$(find results/{wildcards.sample}/decontamination/tiara -name "*probabilities.txt" | head -n 1)
        
        if [ -n "$FOUND" ]; then
            # Jika ketemu, rename sesuai keinginan Snakemake
            mv "$FOUND" {output.prob}
        else
            # Jika TIDAK ketemu, buat file kosong (dummy) agar workflow tidak crash.
            # File ini tidak dipakai di step selanjutnya, jadi aman.
            echo "WARNING: Tiara tidak menghasilkan file probabilities. Membuat dummy file."
            touch {output.prob}
        fi
        """

# 2.b. Filtering (Membuang Bakteri/Archaea/Unknown)
# (Bagian ini TIDAK PERLU DIUBAH, tapi pastikan inputnya benar)
rule tiara_filtering:
    input:
        fasta          = "results/{sample}/decontamination/fcs/clean.fasta",
        classification = "results/{sample}/decontamination/tiara/classification.txt"
    output:
        final_genome = "results/{sample}/final_genome/final_clean.fasta",
        rejected_ids = "results/{sample}/final_genome/rejected_ids.txt"
    conda:
        "../envs/decon.yaml"
    shell:
        """
        # 1. Buat daftar ID yang disimpan (Eukarya + Organel tumbuhan)
        awk '$2 == "eukarya" || $2 == "mitochondria" || $2 == "plastid" {{print $1}}' {input.classification} > results/{wildcards.sample}/decontamination/tiara/keep_list.txt
        
        # 2. Filter FASTA
        seqkit grep -f results/{wildcards.sample}/decontamination/tiara/keep_list.txt {input.fasta} > {output.final_genome}
        
        # 3. Log reject
        awk '$2 != "eukarya" && $2 != "mitochondria" && $2 != "plastid" {{print $0}}' {input.classification} > {output.rejected_ids}
        """