# =============================================================================
# STEP 1: FCS-ADAPTOR (Technical Cleaning: Adapters & Vectors)
# =============================================================================

# 1.a. Download Resource FCS (Sekali saja)
rule fcs_setup:
    output:
        wrapper = "resources/fcs/run_fcsadaptor.sh",
        cleaner = "resources/fcs/fcs.py",
        sif     = "resources/fcs/fcs-adaptor.sif"
    shell:
        """
        mkdir -p resources/fcs
        # Download Wrapper & Script
        curl -L https://github.com/ncbi/fcs/raw/main/dist/run_fcsadaptor.sh -o {output.wrapper}
        chmod 755 {output.wrapper}
        curl -L https://github.com/ncbi/fcs/raw/main/dist/fcs.py -o {output.cleaner}
        # Download Image SIF (BioContainers/NCBI)
        curl -L https://ftp.ncbi.nlm.nih.gov/genomes/TOOLS/FCS/releases/latest/fcs-adaptor.sif -o {output.sif}
        """

# 1.b. Screening (Mencari Adapter)
rule fcs_screen:
    input:
        assembly = "results/medaka/{sample}/consensus.fasta",
        wrapper  = "resources/fcs/run_fcsadaptor.sh",
        sif      = "resources/fcs/fcs-adaptor.sif"
    output:
        report_dir = directory("results/fcs_adaptor/{sample}"),
        report_txt = "results/fcs_adaptor/{sample}/fcs_adaptor_report.txt"
    threads: 8
    params:
        tax_group = "--euk" # Tanaman adalah Eukariota
    shell:
        """
        # Gunakan path absolut untuk image
        SIF_PATH="$PWD/{input.sif}"
        
        {input.wrapper} \
            --fasta-input {input.assembly} \
            --output-dir {output.report_dir} \
            {params.tax_group} \
            --container-engine singularity \
            --image $SIF_PATH
        """

# 1.c. Cleaning (Membuang Adapter)
rule fcs_clean:
    input:
        assembly = "results/medaka/{sample}/consensus.fasta",
        report   = "results/fcs_adaptor/{sample}/fcs_adaptor_report.txt",
        cleaner  = "resources/fcs/fcs.py"
    output:
        clean_fasta  = "results/fcs_adaptor/{sample}_clean.fasta",
        contam_fasta = "results/fcs_adaptor/{sample}_contam.fasta"
    conda:
        "../envs/fcs.yaml"
    shell:
        """
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
        # INPUTNYA ADALAH OUTPUT DARI FCS (Chained)
        fasta = "results/fcs_adaptor/{sample}_clean.fasta"
    output:
        classification = "results/tiara/{sample}/classification.txt",
        prob           = "results/tiara/{sample}/probabilities.txt"
    conda:
        "../envs/decon.yaml"
    threads: 8
    shell:
        """
        tiara -i {input.fasta} \
              -o {output.classification} \
              --prob {output.prob} \
              -m 1000 \
              --tf mit pla \
              -t {threads}
        """

# 2.b. Filtering (Membuang Bakteri/Archaea)
rule tiara_filtering:
    input:
        fasta          = "results/fcs_adaptor/{sample}_clean.fasta",
        classification = "results/tiara/{sample}/classification.txt"
    output:
        final_genome = "results/final_genome/{sample}_final_clean.fasta",
        rejected_ids = "results/final_genome/{sample}_rejected_ids.txt"
    conda:
        "../envs/decon.yaml"
    shell:
        """
        # Simpan: Eukarya (inti), Mitochondria, Plastid (kloroplas)
        awk '$2 == "eukarya" || $2 == "mitochondria" || $2 == "plastid" {{print $1}}' {input.classification} > results/tiara/{wildcards.sample}/keep_list.txt
        
        # Filter FASTA menggunakan seqkit
        seqkit grep -f results/tiara/{wildcards.sample}/keep_list.txt {input.fasta} > {output.final_genome}
        
        # Simpan log apa saja yang dibuang
        awk '$2 != "eukarya" && $2 != "mitochondria" && $2 != "plastid" {{print $0}}' {input.classification} > {output.rejected_ids}
        """