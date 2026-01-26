# PlantGenotationFlow 🌱

![Snakemake](https://img.shields.io/badge/snakemake-≥7.0.0-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey)

**PlantGenotationFlow** is a comprehensive, modular, and automated **Snakemake** pipeline designed specifically for **Plant Genome Assembly and Annotation**.

It integrates state-of-the-art tools to handle the complexity of plant genomes (large sizes, high repetitiveness, and heterozygosity). The pipeline goes from raw long-reads to a fully annotated GFF3 file.

```text
  _____  _             _   _____                 _        _   _             
 |  __ \| |           | | / ____|               | |      | | (_)            
 | |__) | | __ _ _ __ | || |  __  ___ _ __   ___| |_ __ _| |_ _  ___  _ __  
 |  ___/| |/ _` | '_ \| || | |_ |/ _ \ '_ \ / _ \ __/ _` | __| |/ _ \| '_ \ 
 | |    | | (_| | | | | || |__| |  __/ | | | (_) | || (_| | |_| | (_) | | | |
 |_|    |_|\__,_|_| |_|\__\_____|\___|_| |_|\___/ \__\__,_|\__|_|\___/|_| |_|
                      ______ ______ ______ 
                     |______|______|______|
                            Flow
````

## 🚀 Key Features

  * **Best-in-Class Assembly:** Options for **Flye** (Nanopore R9/R10) and **Hifiasm** (PacBio HiFi/ONT R10), offering flexibility for different long-read technologies.
  * **Comprehensive Quality Control:** Multi-tier QC using **NanoPlot** (Raw Reads), **Filtlong** (Filtering), **QUAST** (Assembly Metrics), and **BUSCO** (Gene Completeness).
  * **Automated Decontamination:** **FCS-Adaptor** integration to screen and remove vector/adaptor contamination before annotation.
  * **Plant-Specific Repeat Masking:** Integrates **EDTA** (De-novo) and **Tetools/RepeatMasker** (Homology-based) specifically optimized for complex plant genomes.
  * **Flexible Annotation:** Choose between **Liftoff** (Mapping-based) for high-quality reference transfer or **Tetools/Galba** for repeat-rich contexts.
  * **Modular & Scalable:** Built on Snakemake modules (`.smk`), allowing easy maintenance and processing of multiple plant samples via a simple TSV sheet.
  * **Containerized:** Full support for Singularity/Docker (via FCS, EDTA, Tetools) to avoid dependency hell.

## 🛠️ Workflow

The pipeline consists of modular steps:

```mermaid
graph TD
    A[Raw Reads] -->|QC| B(NanoPlot & Filtlong)
    B -->|Assembly| C{Flye / Hifiasm}
    
    C -->|Draft Assembly| D[Polishing (Medaka)]
    D --> E[Decontamination (FCS-Adaptor & Tiara)]
    
    E -->|Clean Genome| F[Assessment (QUAST & BUSCO)]
    
    F -->|Repeat Masking| G[EDTA / Tetools]
    G --> H[Masked Genome]
    
    H -->|Annotation| I{Liftoff / Galba}
    I --> J((Final GFF3 & HTML Report))
```

## 📂 Directory Structure

```text
PlantGenotationFlow/
├── config/
│   ├── config.yaml          # Main configuration (methods, threads, paths)
│   └── samples.tsv          # Input data sheet
├── workflow/
│   ├── Snakefile            # Main entry point
│   ├── rules/               # Modules (00_qc, 01_assembly, 02_assessment, etc.)
│   ├── envs/                # Conda environments
│   └── scripts/             # Python helper scripts
└── results/                 # Output directory (auto-generated)
```

## 🔧 Installation & Prerequisites

1.  **Clone the repository:**

    ```bash
    git clone [https://github.com/yourusername/PlantGenotationFlow.git](https://github.com/yourusername/PlantGenotationFlow.git)
    cd PlantGenotationFlow
    ```

2.  **Install Snakemake:**
    Recommended via Mamba/Conda:

    ```bash
    conda install -c bioconda -c conda-forge snakemake mamba
    ```

3.  **Dependencies:**

      * **Singularity (Apptainer):** Required for running EDTA and BRAKER3 containers.
      * **Databases:** You need to prepare:
          * BUSCO lineage (e.g., `embryophyta_odb10`)
          * Protein reference FASTA (e.g., Viridiplantae proteins)

## ⚙️ Configuration

### 1\. `config/samples.tsv`

List your samples here. The pipeline can handle multiple genomes in parallel.

| sample\_id | platform | reads\_path |
| :--- | :--- | :--- |
| rice\_indica | hifi | data/raw/rice\_hifi.fq.gz |
| maize\_B73 | hifi | data/raw/maize\_hifi.fq.gz |

### 2\. `config/config.yaml`

Edit this file to customize your workflow, including assembly methods and reference datasets.

```yaml
samples: "config/samples.tsv"

# Referensi
refs:
  genome: "refs/reference.fasta"
  gff: "refs/reference.gff3" # Required for Liftoff

# Assembly Settings
assembly:
  method: "flye" # Options: "flye" or "hifiasm"
  flye:
    mode: "--nano-hq"
  hifiasm:
    extra_args: "--ont"

# Annotation Settings
annotation:
  method: "liftoff" # Options: "liftoff", "tetools", "both"
```

## 🏃 Usage

**Dry run (Test the workflow):**

```bash
snakemake -n
```

**Run the pipeline (Local machine/Server):**
Note: `--use-singularity` is required for EDTA and Tetools steps.

```bash
snakemake --use-conda --use-singularity --cores 32
```

## 📊 Outputs

Upon completion, you will find the results in the `results/` directory:

  * **`results/final_genome/{sample}_final_clean.fasta`**: The polished and decontaminated genome.
  * **`results/qc/`**: Comprehensive QC reports (NanoPlot, QUAST, BUSCO).
  * **`results/annotation/`**: Final GFF3 files (Liftoff/Galba) and HTML summary report.
  * **`results/repeats/`**: EDTA and RepeatMasker Tbl stats.

## 🤝 Contributing

Contributions are welcome\! Please open an issue or submit a pull request.

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
