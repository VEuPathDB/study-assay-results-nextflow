package CBIL::StudyAssayResults::DataMunger::Profiles;
use base qw(CBIL::StudyAssayResults::DataMunger::Loadable);

use strict;

use locale;
use open ":std" => ":locale";

use File::Basename;

use CBIL::StudyAssayResults::Error;

use Data::Dumper;

use File::Temp qw/ tempfile /;



#-------------------------------------------------------------------------------

 sub getSamples                 { $_[0]->{samples} }
 sub setSamples                 { $_[0]->{samples} = $_[1] }

 sub getDyeSwaps                { $_[0]->{dyeSwaps} }
 sub getFindMedian              { $_[0]->{findMedian} }
 sub getPercentileChannel       { $_[0]->{percentileChannel} }

 sub getHasRedGreenFiles        { $_[0]->{hasRedGreenFiles} }
 sub getMakePercentiles         { $_[0]->{makePercentiles} }

 sub getIsTimeSeries            { $_[0]->{isTimeSeries} }
 sub getIsLogged                { $_[0]->{isLogged} }
 sub getBase                    { $_[0]->{base} }

sub getIgnoreStdError          { $_[0]->{ignoreStdErrorEstimation} }
#-------------------------------------------------------------------------------

 # Standard Error is Set internally
 sub getMakeStandardError       { $_[0]->{_makeStandardError} }
 sub setMakeStandardError       { $_[0]->{_makeStandardError} = $_[1] }


sub new {
  my ($class, $args, $subclassRequiredParams) = @_;

  my $sourceIdTypeDefault = 'gene';

  my %requiredParams = ('inputFile', undef,
                        'outputFile', undef,
                        'samples', undef,
                        );

  if($subclassRequiredParams) {
    foreach(@$subclassRequiredParams) {
      $requiredParams{$_}++;
    }
  }

  my @requiredParams = keys %requiredParams;

  unless($args->{doNotLoad} == 1 ) {
    push @requiredParams, 'profileSetName';
  }


  unless ($args->{sourceIdType}) {
    $args->{sourceIdType} = $sourceIdTypeDefault;
  }

  if ($args->{isTimeSeries} && $args->{hasRedGreenFiles} && !$args->{percentileChannel}) {
    CBIL::StudyAssayResults::Error->new("Must specify percentileChannel for two channel time series experiments")->throw();
  }


  unless (defined $args->{isLogged}){
    $args->{isLogged} = 1;
  }

  unless (defined $args->{base}){
    $args->{base} = 2;
  }

  my $self = $class->SUPER::new($args, \@requiredParams);

  my $inputFile = $args->{inputFile};

  unless(-e $inputFile) {
    CBIL::StudyAssayResults::Error->new("input file $inputFile does not exist")->throw();
  }



  return $self;
}


sub munge {
  my ($self) = @_;


  my $samplesRString = $self->makeSamplesRString();

  my $ignoreStdError = $self->getIgnoreStdError();

  if ($ignoreStdError == 0) {
    $self->checkMakeStandardError();
  }

  my $rFile = $self->writeRScript($samplesRString);

  $self->runR($rFile);

  system("rm $rFile");
  my $doNotLoad = $self->getDoNotLoad(); 


  my $samplesHash = $self->groupListHashRef($self->getSamples());

  my @names = keys %$samplesHash;
  $self->setNames(\@names);

  my $outputFile = $self->getOutputFile();

  #  don't want the full path here

  my $outputFileBasename = basename $outputFile;
  my $outputFileDirname = dirname $outputFile;

  # NOTE:  we are adding a "." here to make a hidden directory for some reason
  # maybe because the directory name is exactly the same as the file name??
  my @fileNames = map { my $n = $_;  $n =~ s/\s/_/g; $n=~ s/[\(\)]//g; "${outputFileDirname}/.${outputFileBasename}/$n";} @names;

  $self->setFileNames(\@fileNames);

  $self->setInputProtocolAppNodesHash($samplesHash);

  $self->createConfigFile();
}


sub checkMakeStandardError {
  my ($self) = @_;
  my $samplesHash = $self->groupListHashRef($self->getSamples());
  
   $self->setMakeStandardError(0);

  foreach my $group (keys %$samplesHash) {
    my $samples = $samplesHash->{$group};
    if(scalar @$samples > 1){
      $self->setMakeStandardError(1);
      last;
    }
  }
}

sub writeRScript {
  my ($self, $samples) = @_;

  my $inputFile = $self->getInputFile();
  my $outputFile = $self->getOutputFile();
  my $pctOutputFile = $outputFile . ".pct";
  my $stdErrOutputFile = $outputFile . ".stderr";

  my $inputFileBase = basename($inputFile);

  my ($rfh, $rFile) = tempfile();

  my $hasDyeSwaps = $self->getDyeSwaps() ? "TRUE" : "FALSE";
  my $hasRedGreenFiles = $self->getHasRedGreenFiles() ? "TRUE" : "FALSE";
  my $makePercentiles = $self->getMakePercentiles() ? "TRUE" : "FALSE";
  my $makeStandardError = $self->getMakeStandardError() ? "TRUE" : "FALSE";
  my $findMedian = $self->getFindMedian() ? "TRUE" : "FALSE";

  my $statistic = $self->getFindMedian() ? 'median' : 'average';
  my $isTimeSeries = $self->getIsTimeSeries() ? "TRUE" : "FALSE";
  my $isLogged = $self->getIsLogged() ? "TRUE" : "FALSE";

  $self->addProtocolParamValue("isTwoChannel", $hasRedGreenFiles);
  $self->addProtocolParamValue("statistic", $statistic);
  $self->addProtocolParamValue("isTimeSeries", $isTimeSeries);
  $self->addProtocolParamValue("percentileChannel", $self->getPercentileChannel()) if($self->getHasRedGreenFiles());
  $self->addProtocolParamValue("isLogged", $isLogged);
  $self->addProtocolParamValue("baseX", $self->getBase()) if($isLogged eq "TRUE");

  my $rString = <<RString;

source("$ENV{GUS_HOME}/lib/R/StudyAssayResults/profile_functions.R");

dat = read.table("$inputFile", header=T, sep="\\t", check.names=FALSE);

dat.samples = list();
dye.swaps = vector();
$samples
#-----------------------------------------------------------------------

if($hasDyeSwaps) {
  dat = mOrInverse(df=dat, ds=dye.swaps);
}

reorderedSamples = reorderAndGetColCentralVal(pl=dat.samples, df=dat, computeMedian=$findMedian);
write.table(reorderedSamples\$data, file="$outputFile",quote=F,sep="\\t",row.names=reorderedSamples\$id, col.names=NA);

if($makeStandardError) {
  write.table(reorderedSamples\$stdErr, file="$stdErrOutputFile",quote=F,sep="\\t",row.names=reorderedSamples\$id, col.names=NA);
}
if($hasRedGreenFiles) {
  redDat = read.table(paste("$inputFile", ".red", sep=""), header=T, sep="\\t", check.names=FALSE);
  greenDat = read.table(paste("$inputFile", ".green", sep=""), header=T, sep="\\t", check.names=FALSE);

  if($hasDyeSwaps) {
    newRedDat = swapColumns(t1=redDat, t2=greenDat, ds=dye.swaps);
    newGreenDat = swapColumns(t1=greenDat, t2=redDat, ds=dye.swaps);
  } else {
    newRedDat = redDat;
    newGreenDat = greenDat;
  }

  reorderedRedSamples = reorderAndGetColCentralVal(pl=dat.samples, df=newRedDat);
  reorderedGreenSamples = reorderAndGetColCentralVal(pl=dat.samples, df=newGreenDat);

  write.table(reorderedRedSamples\$data, file=paste("$outputFile", ".red", sep=""), quote=F,sep="\\t",row.names=reorderedRedSamples\$id, col.names=NA);
  write.table(reorderedGreenSamples\$data, file=paste("$outputFile", ".green", sep=""), quote=F,sep="\\t",row.names=reorderedGreenSamples\$id, col.names=NA);
}

if($makePercentiles) {
  if($hasRedGreenFiles) {
    reorderedRedSamples\$percentile = percentileMatrix(m=reorderedRedSamples\$data);
    reorderedGreenSamples\$percentile = percentileMatrix(m=reorderedGreenSamples\$data);

    write.table(reorderedRedSamples\$percentile, file=paste("$outputFile", ".redPct", sep=""), quote=F,sep="\\t",row.names=reorderedRedSamples\$id, col.names=NA);
    write.table(reorderedGreenSamples\$percentile, file=paste("$outputFile", ".greenPct", sep=""), quote=F,sep="\\t",row.names=reorderedGreenSamples\$id, col.names=NA);
  } else {
    reorderedSamples\$percentile = percentileMatrix(m=reorderedSamples\$data);
    write.table(reorderedSamples\$percentile, file="$pctOutputFile",quote=F,sep="\\t",row.names=reorderedSamples\$id, col.names=NA);
  }
}

### Here we make individual files
### Header names match gus4 results tables

  samplesDir = paste(dirname("$outputFile"), "/", ".", basename("$outputFile"), sep="");
  dir.create(samplesDir);

 for(i in 1:ncol(reorderedSamples\$data)) {
   sampleId = colnames(reorderedSamples\$data)[i];

   sample = as.matrix(reorderedSamples\$data[,i]);
   colnames(sample)= c("value");


   if($makeStandardError) {
     stdErrSample = as.matrix(reorderedSamples\$stdErr[,i]);
     colnames(stdErrSample)= c("standard_error");
     
     sample = cbind(sample, stdErrSample);
   }


   if($makePercentiles) {
     if($hasRedGreenFiles) {
       redPctSample = as.matrix(reorderedRedSamples\$percentile[,i]);
       colnames(redPctSample)= c("percentile_channel1");
       sample = cbind(sample, redPctSample);

       greenPctSample = as.matrix(reorderedGreenSamples\$percentile[,i]);
       colnames(greenPctSample)= c("percentile_channel2");
       sample = cbind(sample, greenPctSample);

     } else {

       pctSample = as.matrix(reorderedSamples\$percentile[,i]);
       colnames(pctSample)= c("percentile_channel1");
       sample = cbind(sample, pctSample);
     }
   }

   # simply replace spaces w/ underscore
   sampleFile = gsub(\" \", \"_\", sampleId, fixed=TRUE);
   sampleFile = gsub(\"(\", \"\", sampleFile, fixed=TRUE);
   sampleFile = gsub(\")\", \"\", sampleFile, fixed=TRUE);

   write.table(sample, file=paste(samplesDir, "/", sampleFile, sep=""),quote=F,sep="\\t",row.names=reorderedSamples\$id, col.names=NA);
 }


quit("no");
RString

  binmode $rfh, ':encoding(UTF-8)';
  print $rfh $rString;

  close $rfh;

  return $rFile;
}

sub makeSamplesRString {
  my ($self) = @_;

  my $samplesHash = $self->groupListHashRef($self->getSamples());
  my $dyeSwapsHash = $self->groupListHashRef($self->getDyeSwaps());

  my $rv = "";

  # this is an ordered hash
  foreach my $group (keys %$samplesHash) {
    my $samples = $samplesHash->{$group};

    $rv .= "dat.samples[[\"$group\"]] = c(" . join(',', map { "\"$_\""} @$samples ) . ");\n\n";
  }

  my $n = 1;
  foreach my $dyeSwap (keys %$dyeSwapsHash) {
    $rv .= "dye.swaps[$n] = \"$dyeSwap\";\n\n";
    $n++;
  }

  return $rv;
}


1;
