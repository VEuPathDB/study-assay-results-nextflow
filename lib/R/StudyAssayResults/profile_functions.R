reorderAndGetColCentralVal <- function (pl=NULL, df=NULL, isFirstColNames=TRUE, computeMedian=FALSE) {

  if (is.null(pl) || is.null(df)){
    stop("DataFrame df and pairlist pl must be passed to this function");
  }

  res = list(id=NULL, data=NULL);
  
  if(isFirstColNames) {
   res$id = as.vector(df[,1]);
 }

  groupNames = rownames(summary(pl));

  for(i in 1:length(groupNames)) {
    sampleGroupName = groupNames[i];

    samples = as.vector(pl[[sampleGroupName]]);


    # add NA Column if samplename not found in file
     if(length(samples) == 1 && sum(samples == colnames(dat)) == 0) {
        colCentralVal = rep(NA, nrow(dat));
     }
     else if(computeMedian) {
      colCentralVal = medianSamples(v=samples, df=df);
    } else {
      colCentralVal = meanSamples(v=samples, df=df); 
    }

    if(length(samples) == 1) {
      res$stdErr = cbind(res$stdErr, rep(NA,nrow(dat)));
    }
    else {
      colStdErr = stdErrSamples(v=samples, df=df);
      res$stdErr = cbind(res$stdErr, colStdErr);
    } 
    res$data = cbind(res$data, colCentralVal);
  }

  colnames(res$data) = groupNames;
  colnames(res$stdErr) = groupNames;
  
  return(res);
}

#--------------------------------------------------------------------------------

makeGroupMatrix <- function (v=NULL, df=NULL) {

  if(is.null(v) || is.null(df)) {
    stop("DataFrame df and vector must be passed to this function");
  }

  dfNames = names(df);

  groupMatrix = NULL;
  
  for(i in 1:length(v)) {
    colNm = v[i];

    index = findIndex(array=dfNames, value=colNm);

    groupMatrix = cbind(groupMatrix, df[,index]);
  }
return(groupMatrix);

}

#--------------------------------------------------------------------------------
meanSamples <- function(v=NULL, df=NULL) {
  groupMatrix = makeGroupMatrix(v,df); 
  return(rowMeans(groupMatrix, na.rm=T));
}

#--------------------------------------------------------------------------------

medianSamples <- function(v=NULL, df=NULL) {
  groupMatrix = makeGroupMatrix(v,df); 
  return(apply(groupMatrix,1,median,na.rm=T));
}

#--------------------------------------------------------------------------------

stdErrSamples <- function(v=NULL, df=NULL) {
  groupMatrix = makeGroupMatrix(v,df); 
  return(apply(groupMatrix,1,stdErr));
}

#--------------------------------------------------------------------------------
stdErr <- function(x=NULL) {
      sqrt(var(x,NULL,na.rm=T)/sum(!is.na(x))) 
 }
#--------------------------------------------------------------------------------
findIndex <- function (array=NULL, value=NULL) {
  if (is.null(array) || is.null(value)) {
    stop("Array and value must be passed to findIndex function");
  }

  res=NULL;
  
  for(i in 1:length(array)) {

    if(value == array[i]) {
      return(i);
    }
  }
  print(value);
  stop("Could not findIndex");
}


#--------------------------------------------------------------------------------

percentileMatrix <- function(m=NULL, ties="min") {

  if (is.null(m)) {
    stop("Matrix m must be passed to findIndex function");
  }

  my.rank = vector();
  
  for(j in 1:ncol(m)) {
    my.rank = cbind(my.rank, rank(as.numeric(as.vector(m[,j])), na.last=FALSE, ties.method=c(ties)));
  }
    
  res = (my.rank * 100) / nrow(my.rank);

  colnames(res) = colnames(m);

  return(res);
}

#--------------------------------------------------------------------------------


write.expr.profile.individual.files <- function(p=NULL, m=NULL, v=NULL, ext=".txt") {

  if (is.null(v) || is.null(m) || is.null(p)){
    stop("Matrix m and p and Vector v must be passed to this function");
  }

  filenames = paste(gsub("\\s", "", colnames(m), perl=TRUE), ext, sep="");

  my.colnames = c("id\tmean", "percentile");
  
  for(j in 1:ncol(m)) {
    write.table(cbind(m[,j], p[,j]), file=filenames[j], quote=F, sep="\t", row.names=v, col.names=my.colnames)
  }
}

#--------------------------------------------------------------------------------

mOrInverse <- function (df=NULL, ds=NULL) {

  if (is.null(df) || is.null(ds)){
    stop("data.frame df and vector ds are required.");
  }

  for(j in 1:length(ds)) {
    dye.swap.sample = ds[j];

    df[[dye.swap.sample]] = df[[dye.swap.sample]] * -1;
  }
  
  return(df);
}

#--------------------------------------------------------------------------------

swapColumns <- function (t1=NULL, t2=NULL, ds=NULL) {

  if (is.null(t1) || is.null(t2) || is.null(ds)){
    stop("data.frames t1 and t2 and vector ds are required.");
  }

  for(j in 1:length(ds)) {
    dye.swap.sample = ds[j];

    t1[[dye.swap.sample]] = t2[[dye.swap.sample]];
  }
  
  return(t1);
}

#--------------------------------------------------------------------------------

standardizeProfiles <- function (df=NULL, refColName=NULL) {
  
  if (is.null(df)) {
    stop("data.frame df is required for standardization.");
  }

  res = list(id=NULL, data=NULL);
  stdData = NULL;
  colNames = NULL;

  res$id = as.vector(df[,1]);
  colNames = colnames(df[,2:length(df)]);

  if (is.null(refColName)) {
    divCol = apply(df[,2:length(df)],1,max,na.rm=T);
    stdData = df[,2:length(df)]/divCol;    
  } else {
    divColIndex = findIndex(colnames(df),refColName);
    stdData = df[,2:length(df)]/df[,divColIndex];
  }

  stdData = round(stdData, digits = 4);
  res$data = stdData;
  colnames(res$data) = colNames;

  return(res);

}

#--------------------------------------------------------------------------------
