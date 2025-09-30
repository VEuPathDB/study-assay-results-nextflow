package CBIL::StudyAssayResults::DataMunger::Standardization;
use base qw(CBIL::StudyAssayResults::DataMunger::Profiles);
use strict;

use Data::Dumper;
use File::Temp qw/ tempfile /;
use CBIL::StudyAssayResults::Error;

#-------------------------------------------------------------------------------

sub getRefColName              { $_[0]->{refColName} }

#-------------------------------------------------------------------------------

sub new {
  my ($class, $args) = @_;

  my $self = $class->SUPER::new($args);

  return $self;
}

sub munge {
  my ($self) = @_;

  $self->{doNotLoad} = 1;
  $self->SUPER::munge();

  my $rFile = $self->writeStdRScript();

  $self->runR($rFile);

  $self->{doNotLoad} = undef;
  my $outputFile = $self->getOutputFile();

  my $samples = $self->readFileHeaderAsSamples($outputFile);
  $self->setSamples($samples);
  $self->setInputFile($outputFile);

  $self->SUPER::munge();

  system("rm $rFile");
}

sub writeStdRScript {
  my ($self) = @_;

  my $inputFile = $self->getOutputFile();
  my $outputFile = $self->getOutputFile();
  my $refColName = $self->getRefColName();

  my ($rfh, $rFile) = tempfile();
  my $rString = <<RString;

source("$ENV{GUS_HOME}/lib/R/StudyAssayResults/profile_functions.R");

dat = read.table("$inputFile", header=T, sep="\\t", check.names=FALSE);
standardizedProfiles = standardizeProfiles(df=dat, refColName=$refColName);
write.table(standardizedProfiles\$data, file="$outputFile",quote=F,sep="\\t",row.names=standardizedProfiles\$id, col.names=NA);

quit("no");
RString


  print $rfh $rString;
  close $rfh;
  return $rFile;
}


1;
