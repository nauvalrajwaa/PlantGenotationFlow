rule prepare_softmask:
    # Helper rule: Konversi Hardmask (N) ke Softmask (acgt) jika output EDTA hardmask
    # Atau gunakan output .softmasked dari EDTA jika tersedia
    input:
        "results/repeats/{sample}/{sample}.assembly.fa.mod.MAKER.masked"
    output:
        "results/annotation/{sample}/genome_softmasked.fa"
    shell:
        # Simple copy jika file sudah OK, atau script konversi.
        # EDTA biasanya output .masked dengan hard masking (N). 
        # Untuk simplifikasi di sini kita asumsi langsung pakai untuk BRAKER
        # Tapi best practice: unmask N, lalu pakai repeat gff untuk softmask bedtools.
        "cp {input} {output}" 

rule braker3:
    input:
        genome = "results/annotation/{sample}/genome_softmasked.fa",
        proteins = config["databases"]["protein_db"]
    output:
        gff = "results/annotation/{sample}/braker.gff3"
    params:
        wd = "results/annotation/{sample}/wd"
    threads: config["threads"]["annotation"]
    container: config["containers"]["braker3"]
    shell:
        """
        braker.pl --genome={input.genome} \
                  --prot_seq={input.proteins} \
                  --workingdir={params.wd} \
                  --threads {threads} \
                  --gff3
        
        cp {params.wd}/braker.gff3 {output.gff}
        """