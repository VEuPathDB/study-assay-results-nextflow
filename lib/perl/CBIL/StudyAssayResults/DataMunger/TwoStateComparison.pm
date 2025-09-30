package CBIL::StudyAssayResults::DataMunger::TwoStateComparison;
use base qw(CBIL::StudyAssayResults::DataMunger::Loadable);

use strict;

sub new {
  my ($class, $args) = @_;

  $args->{outputFile} = $args->{inputFile} unless($args->{outputFile});

  my $requiredParams = ['inputFile',
                        'outputFile',
                        'analysisName',
                       ];

  my $self = $class->SUPER::new($args, $requiredParams);

  return $self;
}

sub generateOutputFile {
   my ($self, $conditionAName, $conditionBName, $suffix) = @_;

   my $outputFile = $conditionAName . " vs " . $conditionBName;
   $outputFile = $outputFile . "." . $suffix if($suffix);
   $outputFile =~ s/ /_/g;

   return $outputFile;
 }


sub munge {
  my ($self) = @_;

  $self->setProtocolName("differential expression analysis data transformation");

  $self->setNames([$self->{analysisName}]);
  $self->setProfileSetName($self->{analysisName});
  $self->setFileNames([$self->getOutputFile()]);


  $self->createConfigFile();
}



1;

