package CBIL::StudyAssayResults::DataMunger::MapIdentifiersAndAverageRows;
use base qw(CBIL::StudyAssayResults::DataMunger);

use strict;

use CBIL::StudyAssayResults::Error;
use CBIL::StudyAssayResults::Check::ConsistentIdOrder;

use File::Temp qw/ tempfile /;
use File::Basename;

use Data::Dumper;

#-------------------------------------------------------------------------------

sub getDataDirPath             { $_[0]->{_data_dir_path} }
sub setDataDirPath             { $_[0]->{_data_dir_path} = $_[1] }

sub getMainDirectory           { $_[0]->{mainDirectory} }
sub setMainDirectory           { $_[0]->{mainDirectory} = $_[1] }

sub getIdColumnName            { $_[0]->{idColumnName} }

sub mappingFileIsTemp { $_[0]->{mapping_file_is_temp} }

#--------------------------------------------------------------------------------

my $MAP_HAS_HEADER = 1;
my $MAP_GENE_COL = 'first';
my $MAP_OLIGO_COL = 'second';

#--------------------------------------------------------------------------------

sub new {
  my ($class, $args) = @_;

  my $self = $class->SUPER::new($args);

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

  unless($self->getMappingFile()) {
    $self->{mappingFile} = $self->makeSelfMappingFile();

  }


  return $self;
}

#--------------------------------------------------------------------------------

sub munge {
  my ($self) = @_;

  my $checker = $self->getChecker();
  my $idArray = $checker->getIdArray();

  # The tmpMappingFile is the distinct oligo->gene mapping
  my $tmpMappingFile = $self->mappingFileForR($idArray);


  my $dataDirPath = $self->getMainDirectory();
  my $dataFile = $dataDirPath . "/" . ($self->getDataFiles())->[0]; # only 1 file


#  print STDOUT "\n\n*** call to writeRScript(with $dataFile, AND $tmpMappingFile)\n";

  my $rFile = $self->writeRScript($dataFile, $tmpMappingFile);
  $self->runR($rFile);

  unlink($rFile, $tmpMappingFile);

  if($self->mappingFileIsTemp()) {
    unlink $self->getMappingFile();
  }
}

#--------------------------------------------------------------------------------

sub readMappingFile {
  my ($self) = @_;

  my $mappingFile = $self->getMappingFile();
  open(MAP, $mappingFile) or CBIL::StudyAssayResults::Error->new("Cannot open file $mappingFile for reading: $!")->throw();

  if($self->hasHeader()) {
    <MAP>;
  }

  my %rv;

  while(<MAP>) {
    chomp;

    my ($unique, $nonUnique) = split(/\t/, $_);
    $rv{$unique} = $nonUnique;
  }
  close MAP;

  return \%rv;
}

#--------------------------------------------------------------------------------

## input : got from reading data file (which already should have genes mapped)
## v = as.vector(inputt[,1]);  (gene_ids column)
## dat = dat[,2:ncol(input)]   (half-life-value matrix)

sub writeRScript {
  my ($self, $dataFile,$mappingFile) = @_;


  my $outputFile = $self->getOutputFile();
  my $outputFileBase = basename($outputFile);
  my $pathToDataFiles = $self->getMainDirectory();

  my ($rfh, $rFile) = tempfile();

  my $rString = <<RString;
source("$ENV{GUS_HOME}/lib/R/StudyAssayResults/normalization_functions.R");

# reading in the mapping file; in which the 2nd coln is the gene_list...
idMap = read.table("$mappingFile", sep="\\t", header=TRUE, na.strings=c(""));
v = as.vector(idMap[,2]);


dat = read.table("$dataFile", sep="\\t", header=TRUE, check.names=FALSE);
dataMatrix = as.matrix(dat[,2:ncol(dat)]);

# Avg Rows
avg.data = averageSpottedReplicates(m=dataMatrix, nm=v, nameIsList=TRUE);

colnames(avg.data) = colnames(dat);

# write data
write.table(avg.data, file="$outputFile", quote=F, sep="\\t", row.names=FALSE);
RString

  print $rfh $rString;

  close $rfh;

  return $rFile;
}



sub makeSelfMappingFile {
  my ($self) = @_;
  my $inputFile = $self->getDataFiles()->[0];

  my $mappingFileHandle = File::Temp->new(UNLINK => 0);
  my $mappingFile = $mappingFileHandle->filename;

  open (INPUT, "<$inputFile") or die "unable to open input file $inputFile : $!";
  open (MAPPING, ">$mappingFile") or die "unable to open input file $inputFile : $!";
  my $isHeader = 1;
  while(<INPUT>) {
    unless ($isHeader) {
      my ($id) = split(/\t/,$_);
      print MAPPING "$id\t$id\n";
    }
    else {
      $isHeader = 0;
      next;
    }
  }
  close INPUT;
  close MAPPING;
  $self->{mapping_file_is_temp} = 1;

  return $mappingFile;
}

1;


