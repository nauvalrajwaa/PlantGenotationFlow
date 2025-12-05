rule qc_quast:
    input:
        "results/assembly/{sample}/{sample}.assembly.fa"
    output:
        "results/qc/quast/{sample}/report.html"
    # MENGGUNAKAN FILE YAML
    conda: "../envs/qc.yaml"
    shell:
        "quast {input} -o results/qc/quast/{wildcards.sample} --threads {threads}"

# Catatan: Untuk BUSCO, jika Anda tetap ingin pakai Container (Docker), 
# Anda tidak perlu mengubah conda env. Tapi jika ingin versi Conda:
rule qc_busco:
    input:
        "results/assembly/{sample}/{sample}.assembly.fa"
    output:
        "results/qc/busco/{sample}/short_summary.txt"
    params:
        lineage = config["databases"]["busco_lineage"],
        out_path = "results/qc/busco",
        out_name = "{sample}"
    threads: 16
    # Opsi 1: Tetap Container (Direkomendasikan agar database stabil)
    container: config["containers"]["busco"]
    # Opsi 2: Pakai Conda (Uncomment baris bawah, hapus baris container)
    # conda: "../envs/qc.yaml" 
    shell:
        """
        busco -i {input} \
              -o {params.out_name} \
              --out_path {params.out_path} \
              -l {params.lineage} \
              -m genome \
              -c {threads} -f
        """