package CBIL::StudyAssayResults::DataMunger::ProfileDifferences;
use base qw(CBIL::StudyAssayResults::DataMunger::Profiles);

use strict;

use CBIL::StudyAssayResults::Error;

use File::Temp qw/ tempfile /;

sub getMinuendFile            { $_[0]->{minuendFile} }
sub getSubtrahendFile         { $_[0]->{subtrahendFile} }

sub new {
  my ($class, $args) = @_;

  my $requiredParams = ['outputFile',
                        'minuendFile',
                        'subtrahendFile',
                       ];

  $args->{inputFile} = '.';
  $args->{samples} = 'PLACEHOLDER';

  my $self = $class->SUPER::new($args, $requiredParams);

  unless(-e $self->getMinuendFile() && -e $self->getSubtrahendFile()) {
    CBIL::StudyAssayResults::Error->("Missing subtrahend or minuend File")->throw();
  }


  return $self;
}


sub munge {
  my ($self) = @_;

  my $minuendFile = $self->getMinuendFile();
  my $subtrahendFile = $self->getSubtrahendFile();

  my $outputFile = $self->getOutputFile();

  my ($tempFh, $tempFn) = tempfile();

  my $header = 'TRUE';

  my $rString = <<RString;

source("$ENV{GUS_HOME}/lib/R/StudyAssayResults/profile_functions.R");

dat1 = read.table("$minuendFile", header=$header, sep="\\t", check.names=FALSE, row.names=1);
dat2 = read.table("$subtrahendFile", header=$header, sep="\\t", check.names=FALSE, row.names=1);

if(!(nrow(dat1) == nrow(dat2))) {
  stop("Different Number or rows in input files");
}

if(sum(rownames(dat1) == rownames(dat2)) != nrow(dat1)) {
  stop("Identifiers are in a different order in input files");
}

datDifference = dat1 - dat2;

output = cbind(rownames(dat1), datDifference);

write.table(output, file="$outputFile", quote=FALSE, sep="\\t", row.names=FALSE);

quit("no");
RString

  print $tempFh $rString;

  $self->runR($tempFn);


  my $samples = $self->readFileHeaderAsSamples($outputFile);
  $self->setSamples($samples);
  $self->setInputFile($outputFile);

  $self->SUPER::munge();

  unlink($tempFn);
}

1;
