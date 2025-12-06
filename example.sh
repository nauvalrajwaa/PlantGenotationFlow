## example data to dry run the pipeline ##

cd /refs

wget -qO- ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR217/003/ERR2173373/ERR2173373.fastq.gz \
  | zcat \
  | head -n 400000 \
  | gzip > /content/drive/MyDrive/arabidopsis_dryrun.fastq.gz

wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/735/GCF_000001735.3_TAIR10/GCF_000001735.3_TAIR10_genomic.fna.gz
wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/735/GCF_000001735.3_TAIR10/GCF_000001735.3_TAIR10_protein.faa.gz
wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/735/GCF_000001735.3_TAIR10/GCF_000001735.3_TAIR10_genomic.gff.gz
wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/735/GCF_000001735.3_TAIR10/GCF_000001735.3_TAIR10_cds_from_genomic.fna.gz

gunzip GCF_000001735.3_TAIR10_genomic.fna.gz
gunzip GCF_000001735.3_TAIR10_protein.faa.gz
gunzip GCF_000001735.3_TAIR10_genomic.gff.gz
gunzip GCF_000001735.3_TAIR10_cds_from_genomic.fna.gz