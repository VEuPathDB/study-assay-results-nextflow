package CBIL::StudyAssayResults::DataMunger::Normalization::OneChannelQuantile;
use base qw(CBIL::StudyAssayResults::DataMunger::Normalization);

use strict;

use CBIL::StudyAssayResults::Utils;
use CBIL::StudyAssayResults::Error;

use CBIL::StudyAssayResults::Check::ConsistentIdOrder;

use File::Basename;
use File::Temp qw/ tempfile /;

#--------------------------------------------------------------------------------

sub getIdColumnName                        { $_[0]->{idColumnName} }
sub getGreenColumnName                     { $_[0]->{greenColumnName} }
sub getGreenBkgColumnName                  { $_[0]->{greenBkgColumnName} }
sub getFlagColumnName                      { $_[0]->{flagColumnName} }

sub getExcludeSpotsByFlagValue             { $_[0]->{excludeSpotsByFlagValue} }

#--------------------------------------------------------------------------------

my $MAP_HAS_HEADER = 0;
my $MAP_GENE_COL = 'first';
my $MAP_OLIGO_COL = 'second';

#--------------------------------------------------------------------------------

sub new {
  my ($class, $args) = @_;

  my $self = $class->SUPER::new($args);

  my $additionalRequiredParams = ['greenColumnName',
                                  'greenBkgColumnName',
                                  'idColumnName',
                                  'flagColumnName',
                                 ];

  CBIL::StudyAssayResults::Utils::checkRequiredParams($additionalRequiredParams, $args);

  $self->setMappingFileHasHeader($MAP_HAS_HEADER) unless(defined $self->getMappingFileHasHeader());
  $self->setMappingFileGeneColumn($MAP_GENE_COL) unless(defined $self->getMappingFileGeneColumn());
  $self->setMappingFileOligoColumn($MAP_OLIGO_COL) unless(defined $self->getMappingFileOligoColumn());

  my $oligoColumn = $self->getMappingFileOligoColumn();
  my $geneColumn = $self->getMappingFileGeneColumn();
  my $hasHeader = $self->getMappingFileHasHeader();

  if($oligoColumn eq $geneColumn) {
    CBIL::StudyAssayResults::Error->new("oligo column cannot be the same as gene column")->throw();
  }

  unless($oligoColumn eq 'first' || $oligoColumn eq 'second') {
    CBIL::StudyAssayResults::Error->new("oligo column must equal first or second")->throw();
  }

  unless($geneColumn eq 'first' || $geneColumn eq 'second') {
    CBIL::StudyAssayResults::Error->new("gene column must equal first or second")->throw();
  }

  my $dataFiles = $self->getDataFiles();
  my $idColumnName = $self->getIdColumnName();
  my $mainDirectory = $self->getMainDirectory();

  my $checker = CBIL::StudyAssayResults::Check::ConsistentIdOrder->new($dataFiles, $mainDirectory, $idColumnName);
  $self->setChecker($checker);

  return $self;
}

sub munge {
  my ($self) = @_;

  my $checker = $self->getChecker();
  my $idArray = $checker->getIdArray();

  my $tmpMappingFile = $self->mappingFileForR($idArray);

  my $dataFilesRString = $self->makeDataFilesRString();

  my $rFile = $self->writeRScript($dataFilesRString, $tmpMappingFile);

  $self->runR($rFile);

  unlink($rFile, $tmpMappingFile);
}


sub writeRScript {
  my ($self, $dataFilesString, $mappingFile) = @_;

  my $outputFile = $self->getOutputFile();
  my $outputFileBase = basename($outputFile);
  my $pathToDataFiles = $self->getMainDirectory();

  my $gf = $self->getGreenColumnName();
  my $gb = $self->getGreenBkgColumnName();
  my $flags = $self->getFlagColumnName();

  my $excludeFlagValue = $self->getExcludeSpotsByFlagValue();

  my ($rfh, $rFile) = tempfile();

  my $rString = <<RString;
load.marray = library(marray, logical.return=TRUE);

if(load.marray) {

source("$ENV{GUS_HOME}/lib/R/StudyAssayResults/normalization_functions.R");

my.gnames = read.marrayInfo("$mappingFile", info.id=c(1,2), labels=1, na.strings=c(""))

data.files = vector();
$dataFilesString

raw.data = read.marrayRaw(data.files, path="$pathToDataFiles", name.Gf="$gf", name.Gb="$gb", name.W="$flags", gnames=my.gnames, skip=0);

raw.data\@maGf = raw.data\@maGf - raw.data\@maGb;

# set raw values for any flags to NA
flagged.values = setFlaggedValuesToNA(rM=raw.data\@maGf, gM=raw.data\@maGf, wM=raw.data\@maW, fv="$excludeFlagValue");

raw.data\@maGf = flagged.values\$G;

quantileNorm = log2(normalizeBetweenArrays(raw.data\@maGf, method="quantile"));

# Avg Spotted Replicates based on "genes" in Mapping File
avgQuantile = averageSpottedReplicates(m=quantileNorm, nm=raw.data\@maGnames\@maInfo[,2]);
avgGreen = averageSpottedReplicates(m=raw.data\@maGf, nm=raw.data\@maGnames\@maInfo[,2]);

colnames(avgQuantile) = c("ID", data.files);
colnames(avgGreen) = c("ID", data.files);

# write data
write.table(avgQuantile, file="$outputFile", quote=F, sep="\\t", row.names=FALSE);
write.table(avgGreen, file=paste("$outputFile", ".green", sep=""), quote=F, sep="\\t", row.names=FALSE);

} else {
  stop("ERROR:  could not load required marray library");
}
RString

  print $rfh $rString;

  close $rfh;

  return $rFile;
}


1;
