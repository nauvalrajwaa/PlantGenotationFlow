#!/bin/bash

# ==============================================================================
# SCRIPT FINAL: TE Library Prep (Dfam 3.9 + RepBase) - FIXED PYTHON FILES
# ==============================================================================

set -e # Stop on error

# --- KONFIGURASI ---
WORKDIR="TE_Library_Prep"
OUTPUT_LIB="final_curated_lib.fa"
TAXON_CLADE="Rosids" 
DFAM_VER="3.9" 

# URL
DFAM_BASE_URL="https://www.dfam.org/releases/Dfam_${DFAM_VER}/families/FamDB"
REPBASE_GIT_URL="https://github.com/yjx1217/RMRB.git" 
# URL Raw GitHub RepeatMasker
RM_GITHUB_BASE="https://raw.githubusercontent.com/rmhubley/RepeatMasker/master"

# --- 1. SETUP FOLDER ---
echo ">>> [1/6] Persiapan Environment..."
mkdir -p $WORKDIR/downloads
mkdir -p $WORKDIR/scripts
mkdir -p $WORKDIR/dfam_db
cd $WORKDIR

# Cek h5py
if ! python3 -c "import h5py" &> /dev/null; then
    echo "    Installing h5py..."
    pip install h5py --user
else
    echo "    Library 'h5py' aman."
fi

# --- 2. DOWNLOAD SCRIPT PYTHON (SESUAI FILE LIST ANDA) ---
echo ">>> [2/6] Menyiapkan Script Python..."

# Buat embl2fasta.py (Converter RepBase)
cat << 'EOF' > scripts/embl2fasta.py
#!/usr/bin/env python3
import sys, re, os
def convert(embl, out):
    if not os.path.exists(embl): sys.exit(1)
    with open(embl, 'r', encoding='latin-1') as i, open(out, 'w') as o:
        eid, cls, seqs, in_seq = "", "Unknown", [], False
        for l in i:
            l = l.strip()
            if l.startswith("ID"):
                parts = l.split()
                if len(parts)>=2: eid=parts[1]
                try: 
                    if "repeatmasker;" in l.lower():
                        m = l.split("repeatmasker;")[1].split(";")
                        cls = f"{m[0].strip()}/{m[1].strip()}" if len(m)>1 else "Unknown"
                except: pass
            elif l.startswith("SQ"): in_seq=True
            elif l.startswith("//"):
                if eid and seqs: o.write(f">{eid}#{cls}\n{''.join(seqs)}\n")
                eid, cls, seqs, in_seq = "", "Unknown", [], False
            elif in_seq: seqs.append(re.sub(r'[\d\s]','',l).upper())
if __name__=="__main__": convert(sys.argv[1], sys.argv[2])
EOF

# DOWNLOAD FAMDB FILES (UPDATED LIST)
cd scripts
echo "    Membersihkan file script lama..."
rm -f famdb*.py # Hapus biar bersih

echo "    Mengunduh komponen famdb..."
# Kita download 5 file yang Anda konfirmasi ada di repo
wget "$RM_GITHUB_BASE/famdb.py"
wget "$RM_GITHUB_BASE/famdb_classes.py"
wget "$RM_GITHUB_BASE/famdb_globals.py"
wget "$RM_GITHUB_BASE/famdb_helper_classes.py"
wget "$RM_GITHUB_BASE/famdb_helper_methods.py"

chmod +x famdb.py
cd ..

# --- 3. PROSES REPBASE (SMART SKIP) ---
echo ">>> [3/6] Cek RepBase..."

if [ -s "repbase_converted.fa" ]; then
    echo "    RepBase sudah siap. Skip."
else
    if [ ! -d "downloads/RMRB_Repo" ]; then
        git clone "$REPBASE_GIT_URL" downloads/RMRB_Repo
    fi
    
    # Cari file EMBL
    EMBL_FILE=$(find downloads/RMRB_Repo -name "RMRBSeqs.embl" | head -n 1)
    
    # Jika belum ada, ekstrak tar.gz
    if [ -z "$EMBL_FILE" ]; then
        cd downloads/RMRB_Repo
        TAR=$(ls RepBase*.tar.gz 2>/dev/null | sort -r | head -n 1)
        if [ -n "$TAR" ]; then 
            echo "    Extracting $TAR..."
            tar -xzf "$TAR"
        fi
        cd ../..
        EMBL_FILE=$(find downloads/RMRB_Repo -name "RMRBSeqs.embl" | head -n 1)
    fi

    if [ -n "$EMBL_FILE" ]; then
        python3 scripts/embl2fasta.py "$EMBL_FILE" repbase_converted.fa
    else
        echo "WARNING: RepBase tidak ditemukan. Membuat file kosong."
        touch repbase_converted.fa
    fi
fi

# --- 4. PROSES DFAM 3.9 (SMART SKIP) ---
echo ">>> [4/6] Cek Dfam ${DFAM_VER}..."

# Partition 0 (ROOT)
if [ -f "dfam_db/dfam${DFAM_VER/./}_full.0.h5" ]; then
    echo "    Partition 0 (H5) aman."
elif [ -f "dfam_db/dfam${DFAM_VER/./}_full.0.h5.gz" ]; then
    echo "    Extracting Partition 0..."
    gunzip -f dfam_db/dfam${DFAM_VER/./}_full.0.h5.gz
else
    echo "    Downloading Partition 0..."
    wget --show-progress -O dfam_db/dfam${DFAM_VER/./}_full.0.h5.gz "$DFAM_BASE_URL/dfam${DFAM_VER/./}_full.0.h5.gz"
    gunzip -f dfam_db/dfam${DFAM_VER/./}_full.0.h5.gz
fi

# Partition 5 (ROSIDS)
if [ -f "dfam_db/dfam${DFAM_VER/./}_full.5.h5" ]; then
    echo "    Partition 5 (H5) SUDAH ADA. Skip download/extract."
elif [ -f "dfam_db/dfam${DFAM_VER/./}_full.5.h5.gz" ]; then
    echo "    Partition 5 (GZ) ada. Mengekstrak..."
    gunzip -f dfam_db/dfam${DFAM_VER/./}_full.5.h5.gz
else
    echo "    Downloading Partition 5..."
    wget --show-progress -O dfam_db/dfam${DFAM_VER/./}_full.5.h5.gz "$DFAM_BASE_URL/dfam${DFAM_VER/./}_full.5.h5.gz"
    gunzip -f dfam_db/dfam${DFAM_VER/./}_full.5.h5.gz
fi

# EKSTRAKSI SEQUENCES
echo "    Menjalankan famdb.py untuk extract '$TAXON_CLADE'..."
python3 scripts/famdb.py -i ./dfam_db families \
    -f fasta_name \
    --ancestors \
    --curated \
    "$TAXON_CLADE" > dfam_rosids.fa

# --- 5. FINISHING ---
echo ">>> [5/6] Final Merge..."

if [ -s repbase_converted.fa ] && [ -s dfam_rosids.fa ]; then
    cat repbase_converted.fa dfam_rosids.fa > $OUTPUT_LIB
    echo "SUKSES: Library Gabungan (RepBase + Dfam) dibuat."
elif [ -s dfam_rosids.fa ]; then
    cat dfam_rosids.fa > $OUTPUT_LIB
    echo "WARNING: Hanya Dfam Rosids (RepBase kosong)."
else
    echo "ERROR: Gagal membuat library."
    exit 1
fi

echo "========================================================"
echo "FILE LIBRARY: $(pwd)/$OUTPUT_LIB"
echo "========================================================"