HW3: 
#1. Get the data from GEO. Please look at the class lecture slides 

# Load the packages:
library(GEOquery)
library(limma)
library(data.table)
library(pheatmap)
library(GSEABase)

# download the data following the lecture note 
gd <- getGEO("GSE45735", destdir = "Data/GEO/")
pd <- pData(gd[[1]])
getGEOSuppFiles("GSE45735", makeDirectory=FALSE, baseDir = "Data/GEO/")
## The T14 file is problematic and needs to be fixed by hand

# Note the regular expression to grep file names
files <- list.files(path = "Data/GEO/", pattern = "GSE45735_T.*.txt.gz", full.names = TRUE)
file_list <- lapply(files, read.table, header=TRUE)
# Remove duplicated rows
file_list_unique <- lapply(file_list, function(x){x<-x[!duplicated(x$Gene),]; 
                                                  x <- x[order(x$Gene),]; 
                                                  rownames(x) <- x$Gene;
                                                  x[,-1]})
# Take the intersection of all genes
gene_list <- Reduce(intersect, lapply(file_list_unique, rownames))
file_list_unique <- lapply(file_list_unique, "[", gene_list,)
matrix <- as.matrix(do.call(cbind, file_list_unique))

# Clean up the pData
pd_small <- pd[!grepl("T13_Day8",pd$title),]
pd_small$Day <- sapply(strsplit(gsub(" \\[PBMC\\]", "", pd_small$title),"_"),"[",2)
pd_small$subject <- sapply(strsplit(gsub(" \\[PBMC\\]", "", pd_small$title),"_"),"[",1)
colnames(matrix) <- rownames(pd_small)
  
#2. Use voom and limma to find genes that are differentially expressed at each time point compared to baseline (day 0). Use an FDR cutoff of 0.01.

#create ExpressionSet
eset_hw3 <- ExpressionSet(assayData = matrix+1)
pData(eset_hw3) <- pd_small

#setup the design matrix
design_hw3 <- model.matrix(~subject+Day, eset_hw3)
voom_hw3 <- voom(eset_hw3,design = design_hw3)

#fit the linear model using Limma
lm <- lmFit(voom_hw3, design_hw3)

#calculate the empirical Bayes statistics
eb <- eBayes(lm)

# Find the diffrental expression genes (FDR = 0.01) at each timepoint caompared to Day0
FDR <- 0.01
days <- 1:10
day_list <- vector("list", length(days))
for (i in days) {
  coef<- paste0("DayDay",i)
  df <- topTable(eb, coef=coef, number=Inf, sort.by="none")
  day_list[[i]] <- as.data.table(df)
  day_list[[i]]$significant <- ifelse(day_list[[i]]$adj.P.Val<FDR, "Yes", "No")
  day_list[[i]]$gene <- rownames(df)
  setkey(day_list[[i]], gene)
}

# Create variable indicating whether gene is differentially expressed at any time point
day_list[[1]]$anytime <- ifelse(day_list[[1]]$significant=="Yes", "Yes", "No")
for (i in days[-1]) {
  day_list[[1]]$anytime <- ifelse(day_list[[1]]$significant=="No" & day_list[[i]]$significant=="Yes", "Yes", day_list[[1]]$anytime)
}

# Create data frame of logFC values relative to day 0 at each time point
setnames(day_list[[1]],"logFC","Day 1")
hw3_dt <- day_list[[1]][, c("AveExpr","t","P.Value","adj.P.Val","B","significant"):=NULL]
for (i in 2:length(days)) {
  setnames(day_list[[i]], "logFC", paste("Day",i))
  day_list[[i]][, c("AveExpr","t","P.Value","adj.P.Val","B","significant"):=NULL]
  hw3_dt <- merge(hw3_dt, day_list[[i]], all.x=TRUE)
}
hw3_df <- data.frame(hw3_dt)
rownames(hw3_df) <- hw3_dt$gene
colnames(hw3_df) <- colnames(hw3_dt)

# Delete rows corresponding to genes not differentially expressed at any time point
hw3_df <- hw3_df[hw3_df$anytime=="Yes",]

# Delete extraneous columns
hw3_df$gene <- NULL
hw3_df$anytime <- NULL
hw3_m <- data.matrix(hw3_df)

#Display your results using pheatmap showing the log fold-change of the differentially expressed genes grouped by time point.  
pheatmap(hw3_m,cluster_cols=FALSE,scale="row") 

#3. Perform a GSEA analysis using camera and the MSigDB Reactome pathway gene signatures. 
# Obtain gene indices for camera 
gsea_set_hw3 <- getGmt("c2.cp.reactome.v4.0.symbols.gmt") # Note: first thing is to manually download the Reactome gene sets
gene_ids_hw3 <- geneIds(gsea_set_hw3)
sets_geneid_hw3 <- symbols2indices(gene_ids_hw3, rownames(eset_hw3))

# Find the gene sets over time
desets_list <- vector("list", length(days))
subjects <- length(unique(pData(eset_hw3)$subject))
for (i in days) {
  cont <- paste0("DayDay",i)
  cont_matrix <- makeContrasts(cont, levels=design_hw3)
  desets_list[[i]] <- camera(voom_hw3, index=sets_geneids_hw3, design=design_hw3, contrast=cont_matrix)
}

# Draw heatmap of enriched gene sets over time
PValue <- sapply(desets_list, function(x){ifelse(x$Direction=="Up", -10*log10(x$PValue), 10*log10(x$PValue))})
rownames(PValue) <- rownames(desets_list[[1]])
PValue_max <- rowMax(abs(PValue))
PValue_small <- PValue[PValue_max>30, ]
anno <- data.frame(Time=paste0("Day",days))
rownames(anno) <- colnames(PValue_small)  <- paste0("Day",days)

#Display your results using pheatmap, again group by timepoint.
pheatmap(PValue_small, cluster_cols=FALSE, scale="row")
