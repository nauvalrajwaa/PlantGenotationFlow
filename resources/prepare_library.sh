#!/bin/bash

# ==============================================================================
# SCRIPT OTOMATIS: Persiapan Library TE (RepBase via Git + Dfam Rosids)
# ==============================================================================

set -e # Script berhenti jika ada error

# --- KONFIGURASI ---
WORKDIR="TE_Library_Prep"
OUTPUT_LIB="final_curated_lib.fa"
TAXON_CLADE="Rosids" # Target: Durian & Cempedak

# URL Sumber Data
REPBASE_GIT_URL="https://github.com/yjx1217/RMRB.git"
DFAM_BASE_URL="https://www.dfam.org/releases/Dfam_3.9/families/FamDB"
FAMDB_SCRIPT_URL="https://raw.githubusercontent.com/rmhubley/RepeatMasker/master/famdb.py"

# --- 1. PERSIAPAN FOLDER ---
echo ">>> [1/6] Membuat folder kerja di: $WORKDIR..."
mkdir -p $WORKDIR/downloads
mkdir -p $WORKDIR/scripts
mkdir -p $WORKDIR/dfam_db
cd $WORKDIR

# --- 2. MEMBUAT SCRIPT PYTHON KONVERTER (Sesuai Kode Anda) ---
echo ">>> [2/6] Membuat script konverter (embl2fasta.py)..."
cat << 'EOF' > scripts/embl2fasta.py
#!/usr/bin/env python3
import sys
import re

def convert_embl_to_fasta(embl_file, output_file):
    print(f"Converting {embl_file}...")
    with open(embl_file, 'r') as infile, open(output_file, 'w') as outfile:
        
        entry_id = ""
        classification = "Unknown"
        sequence_lines = []
        in_sequence = False
        
        for line in infile:
            line = line.strip()
            
            # 1. Parsing Header (ID)
            if line.startswith("ID"):
                parts = line.split()
                if len(parts) >= 2:
                    entry_id = parts[1]
                try:
                    meta_info = line.split("repeatmasker;")[1]
                    classes = [x.strip() for x in meta_info.split(";")]
                    te_class = classes[0] if len(classes) > 0 else "Unknown"
                    te_family = classes[1] if len(classes) > 1 else "Unknown"
                    if te_family == "???": te_family = "Unknown"
                    classification = f"{te_class}/{te_family}"
                except:
                    classification = "Unknown"

            # 2. Parsing Sequence (SQ)
            elif line.startswith("SQ"):
                in_sequence = True
                
            # 3. Akhir Entry (//) -> Tulis ke file
            elif line.startswith("//"):
                if entry_id and sequence_lines:
                    full_seq = "".join(sequence_lines)
                    outfile.write(f">{entry_id}#{classification}\n")
                    outfile.write(f"{full_seq}\n")
                entry_id = ""; classification = "Unknown"; sequence_lines = []; in_sequence = False
                
            # 4. Ambil isi sekuens
            elif in_sequence:
                clean_seq = re.sub(r'[\d\s]', '', line)
                sequence_lines.append(clean_seq)
    print("Selesai.")

if __name__ == "__main__":
    convert_embl_to_fasta(sys.argv[1], sys.argv[2])
EOF

# --- 3. CLONE & PROSES REPBASE ---
echo ">>> [3/6] Mengambil RepBase via Git Clone..."

# Cek apakah folder repo sudah ada, jika belum baru clone
if [ ! -d "downloads/RMRB_Repo" ]; then
    git clone "$REPBASE_GIT_URL" downloads/RMRB_Repo
else
    echo "    Folder Repo sudah ada, melakukan git pull untuk update..."
    cd downloads/RMRB_Repo && git pull && cd ../..
fi

# Path sesuai struktur yang Anda infokan: Libraries/RMRBSeqs.embl
REPBASE_EMBL="downloads/RMRB_Repo/Libraries/RMRBSeqs.embl"

if [ ! -f "$REPBASE_EMBL" ]; then
    echo "ERROR: File tidak ditemukan di $REPBASE_EMBL"
    echo "Cek struktur folder repo!"
    exit 1
fi

echo "    File ditemukan: $REPBASE_EMBL"
echo "    Mengonversi RepBase EMBL ke FASTA..."
python3 scripts/embl2fasta.py "$REPBASE_EMBL" repbase_converted.fa

# --- 4. DOWNLOAD & PROSES DFAM (PARTISI 0 & 5) ---
echo ">>> [4/6] Mendownload Dfam 3.9 (Root & Rosids)..."

# Download famdb.py
if [ ! -f "scripts/famdb.py" ]; then
    wget -q -O scripts/famdb.py "$FAMDB_SCRIPT_URL"
fi

# Download Partisi 0 (Root - Wajib)
if [ ! -f "dfam_db/dfam39_full.0.h5" ]; then
    echo "    Downloading Partition 0 (Root)..."
    wget -q --show-progress -O dfam_db/dfam39_full.0.h5.gz "$DFAM_BASE_URL/dfam39_full.0.h5.gz"
    gunzip -f dfam_db/dfam39_full.0.h5.gz
fi

# Download Partisi 5 (Rosids - Target Anda)
if [ ! -f "dfam_db/dfam39_full.5.h5" ]; then
    echo "    Downloading Partition 5 (Rosids)..."
    wget -q --show-progress -O dfam_db/dfam39_full.5.h5.gz "$DFAM_BASE_URL/dfam39_full.5.h5.gz"
    gunzip -f dfam_db/dfam39_full.5.h5.gz
fi

echo "    Mengekstrak library '$TAXON_CLADE' dari Dfam..."
# Syarat: pip install h5py
python3 scripts/famdb.py -i ./dfam_db families \
    -f fasta_name \
    --ancestors \
    --curated \
    "$TAXON_CLADE" > dfam_rosids.fa

# --- 5. PENGGABUNGAN ---
echo ">>> [5/6] Menggabungkan Library RepBase & Dfam..."
cat repbase_converted.fa dfam_rosids.fa > $OUTPUT_LIB

# --- 6. SELESAI ---
echo "========================================================"
echo "SUKSES!"
echo "File Library Siap Pakai: $(pwd)/$OUTPUT_LIB"
echo ""
echo "Command untuk EDTA:"
echo "--curatedlib $(pwd)/$OUTPUT_LIB"
echo "========================================================"