package CBIL::StudyAssayResults::DataMunger::NoSampleConfigurationProfiles;
use base qw(CBIL::StudyAssayResults::DataMunger::Profiles);

# Use if you have a tab file and don't want to code the samples property in the configuration file
# The output file will equal the input file;  You must specify whether or not to calculate the percentiles

use strict;

use CBIL::StudyAssayResults::Error;

use Data::Dumper;

use File::Basename;

use File::Temp;


sub new {
  my ($class, $args) = @_;

  my $requiredParams = ['makePercentiles',
                        'inputFile'
                       ];

  $args->{outputFile} = $args->{inputFile};

  my $output = $args->{outputFile};
  
  unless ($args->{isLogged}) {
    $args->{isLogged} = 0;
  }

  my $mainDirectory = $args->{mainDirectory};

  open(FILE, "$mainDirectory/$output") || die "Cannot open file $mainDirectory/$output for reading $!";
  my $header = <FILE>;
  chomp($header);
  my @samples = split('\t',$header);

  shift(@samples);
  close(FILE);

  my @uniq= ();
  my %seen = ( );
  foreach my $item (@samples) {
    push(@uniq, $item) unless $seen{$item}++;
  }
  unless (scalar @samples == scalar(@uniq)){
    die "sample names must be unique, average samples with the profiles step class before calling this step class";
  }
  $args->{samples} = \@samples;





  my $self = $class->SUPER::new($args, $requiredParams);

  return $self;
}

sub munge {
  my ($self) = @_;
  
  $self->SUPER::munge();

}


1;
 
