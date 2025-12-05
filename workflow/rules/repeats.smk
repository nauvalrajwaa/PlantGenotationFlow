rule edta_masking:
    input:
        genome = "results/assembly/{sample}/{sample}.assembly.fa"
    output:
        # EDTA menghasilkan file dengan suffix khusus
        masked = "results/repeats/{sample}/{sample}.assembly.fa.mod.MAKER.masked", 
        stats = "results/repeats/{sample}/{sample}.assembly.fa.mod.EDTA.TEanno.sum"
    params:
        cds = config["databases"]["protein_db"], # Optional: CDS cleaning step
        species = "Rice" # Ganti dengan "Others" atau spesifik (Maize, Rice, Arabidopsis)
    threads: 32
    container: config["containers"]["edta"]
    log: "logs/repeats/{sample}_edta.log"
    shell:
        """
        # Pindah ke directory output agar file temp EDTA rapi
        mkdir -p results/repeats/{wildcards.sample}
        cd results/repeats/{wildcards.sample}
        
        # Link genome file ke sini agar EDTA bisa akses path relatif
        ln -s ../../../{input.genome} genome.fa
        
        EDTA.pl --genome genome.fa \
                --species {params.species} \
                --step all \
                --sensitive 1 \
                --anno 1 \
                --threads {threads} > ../../../{log} 2>&1
        """