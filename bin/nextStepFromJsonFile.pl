#!/usr/bin/perl

use strict;

use Data::Dumper;

use JSON;

my $jsonFile = $ARGV[0];
my $nextStepFile = $ARGV[1];
my $remainingStepsFile = $ARGV[2];
my $classNameFile = $ARGV[3];


open my $fh, '<', $jsonFile or die "Could not open file '$jsonFile': $!";
local $/; # Enable 'slurp' mode
my $jsonText = <$fh>;
close $fh;

# Decode the JSON text into a Perl object
my $jsonParser = JSON->new;
my $stepsAr = $jsonParser->decode($jsonText);


my $nextStep = shift(@$stepsAr);

open(NEXTSTEP, ">$nextStepFile") or die "Cannot open next step file for writing: $!";
open(OUTPUT, ">$remainingStepsFile") or die "Cannot open remaining steps file for writing: $!";


my $class = $nextStep->{class};

my $container = 'veupathdb/gusenv:latest';
if($class eq "ApiCommonData::Load::IterativeWGCNAResults") {
    $container = 'veupathdb/iterativewgcna:latest'
}

print STDOUT $container . "\n";


print NEXTSTEP $jsonParser->encode($nextStep);
close NEXTSTEP;

print OUTPUT $jsonParser->encode($stepsAr);
close OUTPUT;
