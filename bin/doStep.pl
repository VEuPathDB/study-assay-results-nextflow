#!/usr/bin/perl

use strict;

use Getopt::Long;

use JSON;

use CBIL::StudyAssayResults::Error;

use Data::Dumper;

my ($help, $jsonFile, $mainDirectory, $inputFile, $technologyType, $pseudogenesFile);

&GetOptions('help|h' => \$help,
            'json_file=s' => \$jsonFile,
            'main_directory=s' => \$mainDirectory,
            'input_file=s' => \$inputFile,
            'technology_type=s' => \$technologyType,
            'pseudogenes_file=s' => \$pseudogenesFile,
           );

unless(-e $jsonFile) {
  &usage("Error:  json file $jsonFile dies not exist");
}

unless(-d $mainDirectory) {
  &usage("Error:  Main Directory $mainDirectory does not exist.");
}

open my $fh, '<', $jsonFile or die "Could not open file '$jsonFile': $!";

my $jsonText;
while(<$fh>) {
  $jsonText .= $_;
}

close $fh;

# Decode the JSON text into a Perl object
my $jsonParser = JSON->new;
my $stepObj = $jsonParser->decode($jsonText);

my $args = $stepObj->{arguments};
my $class = $stepObj->{class};

while ( my ($key, $value) = each(%$args) ) {
  if ($value =~m/^no$/i || $value =~m/^false$/i ) {
    $args->{ $key } = 0;
  }
  elsif ($value =~m/^yes$/i || $value =~m/^true$/i ) {
    $args->{ $key } = 1;
  }
}

$args->{mainDirectory} = $mainDirectory;

unless($args->{inputFile}) {
  $args->{inputFile} = $inputFile;
}

eval "require $class";
CBIL::StudyAssayResults::Error->new($@)->throw() if $@;
my $dataMunger = eval {
  $class->new($args);
};

CBIL::StudyAssayResults::Error->new($@)->throw() if $@;

$dataMunger->setTechnologyType($technologyType);
$dataMunger->setPseudogenesFile($pseudogenesFile) if($pseudogenesFile);
$dataMunger->munge();

sub usage {
  my $m = shift;

  print STDERR "$m\n\n" if($m);
  die "usage:  perl doStep.pl --xml_file <XML> --main_directory <DIR> [--input_file <FILE>] --help\n";
  
}


1;
