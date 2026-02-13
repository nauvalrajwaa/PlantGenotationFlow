# -----------------------------------------------------------------------------
# REPEAT MASKING WITH EDTA (Singularity/Docker version)
# -----------------------------------------------------------------------------

rule edta_masking:
    input:
        # Input Genome dari Tiara/Cleaning
        genome = "results/{sample}/final_genome/final_clean.fasta",
        
        # CDS (Opsional dari config)
        cds    = config["refs"]["cds"] if "cds" in config["refs"] else [],
        
        ### UPDATE: Input Library TE
        # Use `tetools.te_lib` from config if set, otherwise fall back to
        # the default resources path produced by the prepare script.
        te_lib = config.get("tetools", {}).get("te_lib", "resources/TE_Library_Prep/final_curated_lib.fa")
    
    output:
        masked = "results/{sample}/repeats/genome.fasta.mod.MAKER.masked",
        te_lib = "results/{sample}/repeats/genome.fasta.mod.EDTA.TElib.fa",
        summary= "results/{sample}/repeats/genome.fasta.mod.EDTA.TEanno.sum"
    
    container:
        "docker://quay.io/biocontainers/edta:2.2.0--hdfd78af_1"
        
    params:
        species = config["repeats"]["species"], # Gunakan 'others'
        outdir  = directory("results/{sample}/repeats"),
        
        # Helper untuk argumen CDS
        cds_arg = lambda wildcards, input: f"--cds reference_cds.fasta" if input.cds else ""
        
    threads: 32
    
    shell:
        """
        # --- 0. SET LOCALE (suppress perl/sh locale warnings) ---
        export LC_ALL=C
        export LANG=C
        unset LANGUAGE

        # --- 1. PERSIAPAN LOKASI KERJA ---
        mkdir -p {params.outdir}

        # Copy GENOME ke folder kerja
        cp {input.genome} {params.outdir}/genome.fasta

        # Copy Library TE ke Folder Kerja
        cp {input.te_lib} {params.outdir}/curated_lib.fasta

        # Copy CDS (Jika ada)
        if [ ! -z "{input.cds}" ]; then
            cp {input.cds} {params.outdir}/reference_cds.fasta
        fi

        # Pindah ke directory kerja (PENTING: EDTA harus dijalankan dari folder outputnya)
        cd {params.outdir}

        # --- 2. EKSEKUSI EDTA ---
        # --force 1  : continue even if TIR/Helitron/LTR results are empty (motif not found)
        # --overwrite 0 : preserve completed modules so partial runs resume, not restart

        set +e  # disable exit-on-error so a non-fatal EDTA exit code won't kill the rule
        EDTA.pl --genome genome.fasta \
                --species {params.species} \
                --curatedlib curated_lib.fasta \
                {params.cds_arg} \
                --step all \
                --sensitive 1 \
                --anno 1 \
                --threads {threads} \
                --overwrite 0 \
                --force 1
        EDTA_EXIT=$?
        set -e  # re-enable exit-on-error

        # --- 3. VERIFY OUTPUTS ---
        # Only fail if the critical output files are truly missing
        if [ ! -f genome.fasta.mod.MAKER.masked ]; then
            echo "FATAL: EDTA finished (exit $EDTA_EXIT) but genome.fasta.mod.MAKER.masked not found." >&2
            exit 1
        fi
        if [ ! -f genome.fasta.mod.EDTA.TElib.fa ]; then
            echo "FATAL: EDTA finished (exit $EDTA_EXIT) but genome.fasta.mod.EDTA.TElib.fa not found." >&2
            exit 1
        fi
        if [ ! -f genome.fasta.mod.EDTA.TEanno.sum ]; then
            echo "FATAL: EDTA finished (exit $EDTA_EXIT) but genome.fasta.mod.EDTA.TEanno.sum not found." >&2
            exit 1
        fi

        if [ "$EDTA_EXIT" -ne 0 ]; then
            echo "WARNING: EDTA exited with code $EDTA_EXIT but all required outputs are present. Continuing." >&2
        fi
        """


# =============================================================================
# DOUBLE-LAYER REPEAT MASKING (TEtools: RepeatModeler + RepeatMasker)
# =============================================================================
# Strategy:
#   Layer 1: Build de novo TE library with RepeatModeler, then mask with RepeatMasker
#   Layer 2: Mask the Layer-1 output again using the curated TE library
#   Both layers use soft-masking (-xsmall) so downstream annotation tools
#   (e.g. GALBA/BRAKER) can still read the sequence.
# =============================================================================

# --- Step 1: Build RepeatModeler Database ---
rule repeatmodeler_build:
    input:
        genome = "results/{sample}/final_genome/final_clean.fasta"
    output:
        nsq = "results/{sample}/repeats/repeatmodeler/{sample}.nsq"
    container:
        "docker://dfam/tetools:latest"
    params:
        db_prefix = "results/{sample}/repeats/repeatmodeler/{sample}"
    threads: 4
    shell:
        """
        mkdir -p $(dirname {params.db_prefix})
        BuildDatabase -name {params.db_prefix} {input.genome}
        """

# --- Step 2: Run RepeatModeler (de novo TE library construction) ---
rule repeatmodeler_run:
    input:
        nsq = "results/{sample}/repeats/repeatmodeler/{sample}.nsq"
    output:
        lib = "results/{sample}/repeats/repeatmodeler/{sample}-families.fa"
    container:
        "docker://dfam/tetools:latest"
    params:
        workdir = "results/{sample}/repeats/repeatmodeler"
    threads: 16
    shell:
        """
        # Use absolute path to avoid issues inside containers
        ABSDIR="$(cd {params.workdir} && pwd)"
        cd "$ABSDIR"

        RepeatModeler -database {wildcards.sample} \
                      -threads {threads} \
                      -LTRStruct

        # Verify output exists
        if [ ! -f {wildcards.sample}-families.fa ]; then
            echo "ERROR: RepeatModeler did not produce {wildcards.sample}-families.fa" >&2
            ls -la
            exit 1
        fi
        """

# --- Step 3: RepeatMasker Layer 1 (de novo RepeatModeler library) ---
rule repeatmasker_layer1:
    input:
        genome = "results/{sample}/final_genome/final_clean.fasta",
        lib    = "results/{sample}/repeats/repeatmodeler/{sample}-families.fa"
    output:
        masked = "results/{sample}/repeats/layer1/genome.fa.masked",
        out    = "results/{sample}/repeats/layer1/genome.fa.out",
        tbl    = "results/{sample}/repeats/layer1/genome.fa.tbl"
    container:
        "docker://dfam/tetools:latest"
    params:
        outdir = "results/{sample}/repeats/layer1"
    threads: 8
    shell:
        """
        mkdir -p {params.outdir}
        cp {input.genome} {params.outdir}/genome.fa

        RepeatMasker -pa {threads} \
                     -lib {input.lib} \
                     -dir {params.outdir} \
                     -xsmall \
                     -gff \
                     {params.outdir}/genome.fa

        # Fallback: if RepeatMasker found zero repeats, .masked may not exist
        if [ ! -f {output.masked} ]; then
            cp {params.outdir}/genome.fa {output.masked}
        fi
        """

# --- Step 4: RepeatMasker Layer 2 (curated TE library) ---
rule repeatmasker_layer2:
    input:
        masked = "results/{sample}/repeats/layer1/genome.fa.masked",
        lib    = config.get("tetools", {}).get("te_lib", "resources/TE_Library_Prep/final_curated_lib.fa")
    output:
        masked = "results/{sample}/repeats/layer2/genome.final_masked.fa",
        out    = "results/{sample}/repeats/layer2/genome.masked.fa.out",
        tbl    = "results/{sample}/repeats/layer2/genome.masked.fa.tbl"
    container:
        "docker://dfam/tetools:latest"
    params:
        outdir = "results/{sample}/repeats/layer2"
    threads: 8
    shell:
        """
        mkdir -p {params.outdir}
        cp {input.masked} {params.outdir}/genome.masked.fa

        RepeatMasker -pa {threads} \
                     -lib {input.lib} \
                     -dir {params.outdir} \
                     -xsmall \
                     -gff \
                     {params.outdir}/genome.masked.fa

        # Rename final output; fallback if no new repeats found in layer 2
        if [ -f {params.outdir}/genome.masked.fa.masked ]; then
            mv {params.outdir}/genome.masked.fa.masked {output.masked}
        else
            cp {params.outdir}/genome.masked.fa {output.masked}
        fi
        """