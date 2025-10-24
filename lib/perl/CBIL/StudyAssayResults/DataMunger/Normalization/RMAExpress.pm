package CBIL::StudyAssayResults::DataMunger::Normalization::RMAExpress;
use base qw(CBIL::StudyAssayResults::DataMunger::Normalization);

use strict;

use CBIL::StudyAssayResults::Error;
use File::Temp qw/ tempfile /;
use File::Basename;

sub getCdfFile                 { $_[0]->getMappingFile }
sub getCelFilePath             { $_[0]->getMainDirectory }

sub munge {
  my ($self) = @_;

  my $dataFilesRString = $self->makeDataFilesRString();

  my $rFile = $self->writeRScript($dataFilesRString);

  $self->runR($rFile);

  unlink($rFile);
}

sub writeRScript {
  my ($self, $samples) = @_;

  my $cdfFile = $self->getCdfFile();
  my $celFilePath = $self->getCelFilePath();
  my $outputFile = $celFilePath . "/" . $self->getOutputFile();

  my ($rfh, $rFile) = tempfile();

  open(RCODE, "> $rFile") or die "Cannot open $rFile for writing:$!";

  my $rString = <<RString;
load.affy = library(affy, logical.return=TRUE);

if(load.affy) {
  data.files = vector();
  $samples

  celPath = "$celFilePath";
  cdfFile = "$cdfFile";

  celFiles = paste(celPath, data.files, sep="/");

  data = ReadAffy(filenames=celFiles, cdfname=cdfFile);
  res = rma(data);

  write.table(exprs(res), file="$outputFile", quote=FALSE, sep="\\t", row.names=TRUE, col.names=NA);

} else {
  stop("ERROR: could not load required library [affy]");
}
RString

  print RCODE $rString;

  close RCODE;

  return $rFile;
}




1;
