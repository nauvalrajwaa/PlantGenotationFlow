# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def get_masked_genome(wildcards):
    repeat_method = config.get("repeats", {}).get("method", "edta")
    if repeat_method == "edta":
        return f"results/{wildcards.sample}/repeats/genome.fasta.mod.MAKER.masked"
    elif repeat_method == "tetools":
        return f"results/{wildcards.sample}/repeats/layer2/genome.final_masked.fa"
    else:
        # Fallback jika tidak ada repeat masking
        return f"results/{wildcards.sample}/final_genome/final_clean.fasta"

def get_repeat_summary(wildcards):
    repeat_method = config.get("repeats", {}).get("method", "edta")
    if repeat_method == "edta":
        return f"results/{wildcards.sample}/repeats/genome.fasta.mod.EDTA.TEanno.sum"
    elif repeat_method == "tetools":
        return f"results/{wildcards.sample}/repeats/layer2/genome.masked.fa.tbl"
    else:
        return []

def get_annotation_stats_inputs(wildcards):
    method = config.get("annotation", {}).get("method", "both")
    inputs = {"repeat_summary": get_repeat_summary(wildcards)}
    
    if method in ("liftoff", "both"):
        inputs["liftoff"] = f"results/{wildcards.sample}/annotation/liftoff.gff3"
    if method in ("galba", "both"):
        inputs["galba"] = f"results/{wildcards.sample}/annotation/galba.gff3"
        
    return inputs

# -----------------------------------------------------------------------------
# 1. LIFTOFF (Metode Utama - DNA Based)
# -----------------------------------------------------------------------------
rule liftoff_annotation:
    input:
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
        target   = get_masked_genome,
        ref_prot = config["refs"]["protein"]
    output:
        gff = "results/{sample}/annotation/galba.gff3"
    container:
        "docker://katharinahoff/galba-notebook:latest"
    threads: 32
    params:
        workdir = "results/{sample}/annotation/galba_out"
    shell:
        """
        # --- 1. SETUP WRITABLE AUGUSTUS CONFIG ---
        if [ -n "${{AUGUSTUS_CONFIG_PATH:-}}" ] && [ -d "$AUGUSTUS_CONFIG_PATH" ]; then
            ORIGINAL_CONFIG="$AUGUSTUS_CONFIG_PATH"
        elif [ -d "/opt/Augustus/config" ]; then
            ORIGINAL_CONFIG="/opt/Augustus/config"
        elif [ -d "/usr/share/augustus/config" ]; then
            ORIGINAL_CONFIG="/usr/share/augustus/config"
        else
            echo "FATAL: Direktori config Augustus tidak ditemukan di dalam container!" >&2
            exit 1
        fi
        
        # GUNAKAN $PWD AGAR MENJADI ABSOLUTE PATH
        export AUGUSTUS_CONFIG_PATH="$PWD/results/{wildcards.sample}/annotation/augustus_config"
        
        # Buat foldernya dan copy isi config bawaan container
        mkdir -p $AUGUSTUS_CONFIG_PATH
        cp -r $ORIGINAL_CONFIG/* $AUGUSTUS_CONFIG_PATH/
        
        # Pastikan direktori spesies benar-benar tercopy
        if [ ! -d "$AUGUSTUS_CONFIG_PATH/species" ]; then
            echo "FATAL: Folder species gagal di-copy ke $AUGUSTUS_CONFIG_PATH" >&2
            exit 1
        fi
        
        # --- 2. JALANKAN GALBA ---
        rm -rf {params.workdir}
        
        galba.pl --genome={input.target} \
                 --prot_seq={input.ref_prot} \
                 --threads {threads} \
                 --workingdir={params.workdir}
                 
        # --- 3. RAPIKAN OUTPUT ---
        if [ -f "{params.workdir}/galba.gtf" ]; then
            cp {params.workdir}/galba.gtf {output.gff}
        else
            echo "FATAL: Galba selesai tetapi file galba.gtf tidak ditemukan di {params.workdir}." >&2
            exit 1
        fi
                 
        # Bersihkan config sementara untuk menghemat ruang
        rm -rf $AUGUSTUS_CONFIG_PATH
        """

# -----------------------------------------------------------------------------
# 3. Summary Stats
# -----------------------------------------------------------------------------
rule annotation_stats:
    input:
        unpack(get_annotation_stats_inputs)
    output:
        summary = "results/{sample}/annotation/stats.txt"
    params:
        repeat_method     = config.get("repeats", {}).get("method", "edta"),
        annotation_method = config.get("annotation", {}).get("method", "both")
    run:
        import subprocess

        with open(output.summary, "w") as out:
            out.write(f"Annotation Statistics for {wildcards.sample}\n")
            out.write("-------------------------------------------\n")
            out.write(f"Annotation method: {params.annotation_method}\n\n")

            if params.annotation_method in ("liftoff", "both") and hasattr(input, "liftoff"):
                out.write("[LIFTOFF] Gene Count:\n")
                cmd = f"awk '$3 == \"gene\"' {input.liftoff} | wc -l"
                res = subprocess.check_output(cmd, shell=True).decode("utf-8").strip()
                out.write(f"{res}\n\n")

            if params.annotation_method in ("galba", "both") and hasattr(input, "galba"):
                out.write("[GALBA] Gene Count:\n")
                cmd = f"awk '$3 == \"gene\"' {input.galba} | wc -l"
                res = subprocess.check_output(cmd, shell=True).decode("utf-8").strip()
                out.write(f"{res}\n\n")

            out.write(f"[REPEAT MASKING] Method: {params.repeat_method}\n")
            if hasattr(input, "repeat_summary") and input.repeat_summary:
                # Amankan jika input.repeat_summary berupa list berukuran 1
                rep_file = input.repeat_summary[0] if isinstance(input.repeat_summary, list) else input.repeat_summary
                with open(rep_file, "r") as rep:
                    out.write(rep.read())

# (Report generation is now handled by the unified generate_pipeline_report rule
#  in 02_assessment.smk → results/reports/index.html)
