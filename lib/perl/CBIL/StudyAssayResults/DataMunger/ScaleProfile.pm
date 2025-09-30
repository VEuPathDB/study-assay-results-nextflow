package CBIL::StudyAssayResults::DataMunger::ScaleProfile;
use base qw(CBIL::StudyAssayResults::DataMunger::Profiles);

use strict;

use CBIL::StudyAssayResults::Error;

use File::Temp qw/ tempfile /;

sub getScalingFactorsFile         { $_[0]->{scalingFactorsFile} }
sub getProfileFile                { $_[0]->{profileFile} }

sub new {
  my ($class, $args) = @_;

  my $requiredParams = ['outputFile',
                        'profileFile'
                       ];

  $args->{samples} = 'PLACEHOLDER';

  if(!$args->{scalingFactorsFile}) {
    $args->{scalingFactorsFile} = $args->{inputFile};
  }

  my $self = $class->SUPER::new($args, $requiredParams);

  unless(-e $self->getProfileFile() && -e $self->getScalingFactorsFile()) {
    CBIL::StudyAssayResults::Error->new("BOTH profileFile and scaling factor file are required.")->throw();
  }

  return $self;
}


sub munge {
  my ($self) = @_;

  my $profileFile = $self->getProfileFile();
  my $scalingFactorsFile = $self->getScalingFactorsFile();

  my $outputFile = $self->getOutputFile();

  my ($tempFh, $tempFn) = tempfile();

  my $header = 'TRUE';

  my $rString = <<RString;

source("$ENV{GUS_HOME}/lib/R/StudyAssayResults/profile_functions.R");

dat1 = read.table("$profileFile", header=$header, sep="\\t", check.names=FALSE, row.names=1);
dat2 = read.table("$scalingFactorsFile", header=$header, sep="\\t", check.names=FALSE, row.names=1);

if(nrow(dat2) != 1) {
  stop("Different Number or rows in input files");
}

if(sum(colnames(dat1) == colnames(dat2)) != ncol(dat1)) {
  stop("Column Headers do not match input files");
}


scaled = NULL;
for(i in 1:ncol(dat1)) {
 # dat2 only has one row by definition
 scaled = cbind(scaled, dat1[,i] * dat2[1,i])
}

output = cbind(rownames(dat1), scaled);
colnames(output) = c("ID", colnames(dat1));

write.table(output, file="$outputFile", quote=FALSE, sep="\\t", row.names=FALSE);

quit("no");
RString

  print $tempFh $rString;

  $self->runR($tempFn);

  my $samples = $self->readFileHeaderAsSamples($outputFile);

  $self->setSamples($samples);
  $self->setInputFile($outputFile);

  $self->setProtocolName("Scaling Data Transformation");

  $self->SUPER::munge();

  unlink($tempFn);
}




1;
