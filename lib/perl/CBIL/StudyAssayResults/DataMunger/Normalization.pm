package CBIL::StudyAssayResults::DataMunger::Normalization;
use base qw(CBIL::StudyAssayResults::DataMunger);

use strict;

use Data::Dumper;

use CBIL::StudyAssayResults::Error;

#-------------------------------------------------------------------------------


sub getDataFiles            { $_[0]->{dataFiles} }

sub isMappingFileZipped     {
  my ($self) = @_;
  my $mappingFile = $self->getMappingFile();

  if($mappingFile =~ /\.gz$/) {
    return 1;
  }
  return 0;
}

#-------------------------------------------------------------------------------

sub new {
  my ($class, $args) = @_;

  my $requiredParams = ['outputFile',
                        'dataFiles',
                        ];

  my $self = $class->SUPER::new($args, $requiredParams);

  my $mappingFile = $self->getMappingFile();

  unless(-e $mappingFile) {
    CBIL::StudyAssayResults::Error->new("Required Mapping file not provided")->throw();
  }

  return $self;
}

sub makeDataFilesRString {
  my ($self) = @_;

  my $dataFilesHash = $self->groupListHashRef($self->getDataFiles());

  my $rv = "";

  my $n = 1;
  # this is an ordered hash
  foreach my $filename (keys %$dataFilesHash) {
    $rv .= "data.files[$n] = \"$filename\";\n";
    $n++;
  }
  return $rv;
}



1;
