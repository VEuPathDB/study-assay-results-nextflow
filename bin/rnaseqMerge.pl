#!/usr/bin/perl

use strict;

use Getopt::Long;

use ApiCommonData::Load::AnalysisConfigRepeatFinder qw(displayAndBaseName);

use Data::Dumper;

my ($help, $dir, $chromSize, $analysisConfig);

&GetOptions('help|h' => \$help,
            'dir=s' => \$dir,
	        'chromSize=s' => \$chromSize,
            'analysisConfig=s' => \$analysisConfig,
            );
      
&usage("RNAseq samples directory not defined") unless $dir;

chomp $dir;

my $sampleHash;
if (-e $analysisConfig) {
    $sampleHash = displayAndBaseName($analysisConfig);
} else {
    die "Analysis config file $analysisConfig cannot be opened for reading\n";
}

my @list;
my $sampleDirName;
foreach my $key (keys %$sampleHash) {
    my $samples = $sampleHash->{$key}->{samples};
    if (scalar @$samples > 1) {
        $sampleDirName = $key ."_combined";
    } elsif (scalar @$samples == 1) {
        $sampleDirName = $samples->[0]
    } else {
        die "No samples found for key $key\n";
    }

    my @files = glob "$dir/normalize_coverage/$sampleDirName/normalized/final/*";

    my @files = grep !/logged/, @files;
    my @files = grep !/non_unique/, @files;
    push @list, @files;
}

my $outDir = "$dir/mergedBigwigs";
&runCmd("mkdir -p $outDir");

if ( grep( /firststrand/, @list ) ) {
  my @firstStrandFileList = grep /firststrand/, @list;
  &convertBigwig(\@firstStrandFileList, $outDir, $chromSize, "firststrand");
}
if ( grep( /secondstrand/, @list ) ) {
  my @secondStrandFileList = grep /secondstrand/, @list;
  &convertBigwig(\@secondStrandFileList, $outDir, $chromSize, "secondstrand");
}
else{
  &convertBigwig(\@list, $outDir, $chromSize, "unstranded");
}

sub convertBigwig {
    my ($fileList, $outDir, $chromSize, $pattern) = @_;

    my $fileNames = join ' ', @$fileList;
    #Check if more than 1 input bigwig file
    if (scalar @$fileList > 1){ 
    my $cmd = "bigWigMerge $fileNames $outDir/out.bedGraph";
    &runCmd($cmd);

	&sortBedGraph ("$outDir\/out\.bedGraph");
    my $convertCmd = "bedGraphToBigWig $outDir/out.bedGraph $chromSize $outDir/$pattern\_merged.bw";
    &runCmd($convertCmd);
    unlink "$outDir/out.bedGraph";
    }
    #If only one bigwig file copy to outdir
    else{
    my $cpCmd = "cp $fileNames $outDir/$pattern\_merged.bw";
    &runCmd($cpCmd);   
    } 
}


sub sortBedGraph {
	my $bedFile = shift;
	my $cmd = "mv $bedFile ${bedFile}.tmp; LC_COLLATE=C sort -k1,1 -k2,2n ${bedFile}.tmp > $bedFile; rm ${bedFile}.tmp"; 
	&runCmd($cmd);

	return $bedFile;
}

sub usage {
  die "rnaseqMerge.pl --dir=s --organism_abbrev=s  --outdir=s --chromSize=s \n";
}

sub runCmd {
    my ($cmd) = @_;

    my $output = `$cmd`;
    my $status = $? >> 8;
    die "Failed with status $status running '$cmd'\n" if $status;
    return $output;
}



1;

