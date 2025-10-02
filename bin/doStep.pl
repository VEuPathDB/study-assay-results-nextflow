#!/usr/bin/perl

use strict;

use Getopt::Long;

use JSON;

use CBIL::StudyAssayResults::Error;

use Data::Dumper;

my ($help, $jsonFile, $mainDirectory, $inputFile, $technologyType, );

&GetOptions('help|h' => \$help,
            'json_file=s' => \$jsonFile,
            'main_directory=s' => \$mainDirectory,
            'input_file=s' => \$inputFile,
            'technology_type=s' => \$technologyType,
           );

unless(-e $jsonFile) {
  &usage("Error:  json file $jsonFile dies not exist");
}

unless(-d $mainDirectory) {
  &usage("Error:  Main Directory $mainDirectory does not exist.");
}

open my $fh, '<', $jsonFile or die "Could not open file '$jsonFile': $!";
local $/; # Enable 'slurp' mode
my $jsonText = <$fh>;
close $fh;

# Decode the JSON text into a Perl object
my $jsonParser = JSON->new;
my $stepObj = $jsonParser->decode($jsonText);


print Dumper $stepObj;

die"";



# foreach my $node (@$nodes) {
#   my $args = $node->{arguments};
#   my $class = $node->{class};

#   while ( my ($key, $value) = each(%$args) ) {
#     if ($value =~m/^no$/i || $value =~m/^false$/i ) {
#       $args->{ $key } = 0;
#     }
#     elsif ($value =~m/^yes$/i || $value =~m/^true$/i ) {
#       $args->{ $key } = 1;
#     }
#   }

#   if (defined $seqIdPrefix) { $args->{seqIdPrefix} = $seqIdPrefix; }
#   if ($patch) { $args->{patch} = 1; }

#   $args->{mainDirectory} = $mainDirectory;

#   unless($args->{inputFile}) {
#     $args->{inputFile} = $inputFile;
#   }

#   eval "require $class";
#   CBIL::StudyAssayResults::Error->new($@)->throw() if $@;
#   my $dataMunger = eval {
#     $class->new($args);
#   };

#   CBIL::StudyAssayResults::Error->new($@)->throw() if $@;

#   $dataMunger->setTechnologyType($technologyType);
#   $dataMunger->setGusConfigFile($gusConfigFile) if($gusConfigFile);
#   $dataMunger->munge();
# }

sub usage {
  my $m = shift;

  print STDERR "$m\n\n" if($m);
  print STDERR "usage:  perl doStudyAssayResults.pl --xml_file <XML> --main_directory <DIR> [--input_file <FILE>] [--seq_id_prefix <SEQ ID PREFIX>] [--patch <use this flag for a patch update>]--help\n";
  exit;
}


1;
