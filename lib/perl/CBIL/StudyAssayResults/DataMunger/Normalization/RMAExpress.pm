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

  my $dataConfigFile = $self->makeDataConfigFile();
  my $optionsConfigFile = $self->makeOptionsConfigFile();
  
  my $systemResult = system("RMAExpressConsole $dataConfigFile $optionsConfigFile");
    
  unless($systemResult / 256 == 0) {
    die"Could not run RMAExpressConsole command";
  }
  unlink($dataConfigFile, $optionsConfigFile);
}

sub makeDataConfigFile {
  my ($self) = @_;

  my $cdfFile = $self->getCdfFile();
  my $dataPath = $self->getCelFilePath();

  my ($fh, $filename) = tempfile();

  print $fh "$cdfFile\n";

  foreach my $celfile (@{$self->getDataFiles()}) {
    print $fh "$dataPath" . "/" . "$celfile\n";
  }

  return $filename;
}

sub makeOptionsConfigFile {
  my ($self) = @_;

  my $dataPath = $self->getCelFilePath();

  my $outputFile = $dataPath . "/" . $self->getOutputFile();

  my ($fh, $filename) = tempfile();

  print $fh "1\n";

  print $fh "$outputFile\n";

  return $filename;
}




1;
