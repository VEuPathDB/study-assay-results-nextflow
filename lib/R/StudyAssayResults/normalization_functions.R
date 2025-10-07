setFlaggedValuesToNA <- function (gM=NULL, rM=NULL, wM=NULL, fv=NULL) {

  if (is.null(gM) || is.null(rM) || is.null(wM) || is.null(fv)){
    stop("gM, rM, and wM matrix required; also flagvalue fv");
  }
  
  for(i in 1:nrow(wM)) {
    for(j in 1:ncol(wM)) {
      if (wM[i,j] == fv) {
        rM[i,j] = NA;
        gM[i,j] = NA;
      }
    }
  }

  res = list(G=gM, R=rM);

  return(res);
}


averageSpottedReplicates <- function (m=NULL, nm=NULL, nameIsList=TRUE) {
  
  if (is.null(m) || is.null(nm)){
    stop("m matrix, and nm vector required;");
  }
  if (length(nm) != nrow(m)) {
    stop("nm vector of different length than matrix m;");
  }
  if (! is.numeric(m)) {
    stop("The m matrix contains non-numeric characters;");
  }

  if(nameIsList) {
  
    newData = vector();
    newName = vector();

    index = 1;
  
    for(i in 1:length(nm)) {
      rowAllNames = unlist(strsplit(as.character(nm[i]), ','));

      for(k in 1:length(rowAllNames)) {
        newName[index] = rowAllNames[k];
        newData = rbind(newData, m[i,]);
        index = index + 1;
      }
    }
  }
  else {
    newData = m;
    newName = nm;
  }

  if (length(newName) != nrow(newData)) {
    stop("newName vector of different length than matrix newData;");
  }

  return(aggregate(newData, list(newName), mean, na.rm=TRUE));
}


#--------------------------------------------------------------------------------
