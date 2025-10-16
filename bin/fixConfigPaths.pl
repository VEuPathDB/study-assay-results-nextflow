#!/usr/bin/perl

use strict;
use File::Copy;

my $configFile = $ARGV[0];
my $outputDirName = $ARGV[1];


my $tempFile = "temp.config";

if (move($configFile, $tempFile)) {
    open(IN, $tempFile) or die "Cannot open file for reading: $!";
    open(OUT, ">$configFile") or die "Cannot open file for writing: $!";

    while(<IN>) {
        chomp;
        my @a = split(/\t/, $_);

        # fix the file path
        $a[1] =~ s/.+\/analysis_output\//$outputDirName\/analysis_output\//;

        print OUT join("\t", @a) . "\n";
    }
    close IN;
    close OUT;
}
else {
    die "Failed to move file: $!";
}

unlink $tempFile;

1;
