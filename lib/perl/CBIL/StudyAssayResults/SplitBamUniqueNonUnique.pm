package CBIL::StudyAssayResults::SplitBamUniqueNonUnique;
use strict;
use warnings;
use CBIL::Util::Utils;
use Exporter qw(import);
our @EXPORT_OK = qw(splitBamUniqueNonUnique);
use CBIL::Util::DnaSeqMetrics;
use Data::Dumper;


sub splitBamUniqueNonUnique {
    my @filesToDelete; 
    my ($expDir, $isStrandSpecific, $isPairedEnd, $file_to_open) = @_;

    die "missing bam file" unless($file_to_open);

    my $filebase = $file_to_open;
    $filebase=~ s/$expDir\///;
    my $unique = "$expDir/unique_".$filebase;
    my $nonunique = "$expDir/non_unique_".$filebase;

    my $statsHash = CBIL::Util::DnaSeqMetrics::runSamtoolsStats($file_to_open);
    my $totalReads = $statsHash->{'raw total sequences'};

   
   
    &runCmd("samtools view -h  $file_to_open  | grep -P '^@|NH:i:([2-9]|1\\d)' |samtools view -h -bS - > $nonunique");
    &runCmd("samtools view -h  $file_to_open | grep -P '^@|NH:i:1(\\s|\$)' |samtools view -h -bS - > $unique");

    open (M, ">$expDir/mappingStats.txt") or die "Cannot open mapping stat file file $expDir/mappingStats.txt for writing\n";
    print M "file\tcoverage\tmapped\tnumber_reads_mapped\taverage_read_length\n";    
  #  print "starting on unique strand bit\n\n\n\n";
    my @mapstat = &mapStats($expDir, $file_to_open, $totalReads);
    print M join("\t", @mapstat) .  "\n"; 
    push @filesToDelete, $unique;
    push @filesToDelete, $nonunique;
 #   print Dumper @filesToDelete;
    &dealWithStrand($expDir, $unique, $isStrandSpecific, $isPairedEnd, $totalReads);
   # print "starting on non_unique strand bit \n\n\n\n";
    &dealWithStrand($expDir, $nonunique, $isStrandSpecific, $isPairedEnd, $totalReads);
    &deleteIntermediateFiles(\@filesToDelete);

    print M "\nDONE STATS\n";
}



sub dealWithStrand {	
    my ($mainResultsDir, $file, $isStrandSpecific, $isPairedEnd, $totalReads) = @_;
    my $baseName = $file;
    my @filesToDelete;
    $baseName =~ s/_sorted.bam//;
    open (M, ">>$mainResultsDir/mappingStats.txt") or die "Cannot open mapping stat file file $mainResultsDir/mappingStats.txt for writing\n";
    if($isStrandSpecific && !$isPairedEnd) {
	print "dataset is strand spec and not paired end\n\n\n\n";
	&runCmd("samtools index $file");
	&runCmd("bamutils tobedgraph -plus $file >${baseName}.firststrand.bed");
	&runCmd("bamutils tobedgraph -minus $file >${baseName}.secondstrand.bed");
#need to split this file anyway to do stats: looking at https://www.biostars.org/p/14378/ unmapped reads are ignored
	&runCmd("samtools view -b -F 20 $file >${baseName}.firststrand.bam");
	&runCmd("samtools view -b -f 16 $file >${baseName}.secondstrand.bam");
	my $forward = $baseName.".firststrand.bam";
	my $reverse = $baseName.".secondstrand.bam";
	push @filesToDelete , $forward;
	push @filesToDelete, $reverse;
	my @mapstat = &mapStats($mainResultsDir, $forward, $totalReads);
	print M join("\t", @mapstat) . "\n";
	@mapstat = &mapStats($mainResultsDir, $reverse, $totalReads);
	print M join("\t", @mapstat) . "\n";
    }
    
    elsif($isStrandSpecific && $isPairedEnd) {
	# modified bash script from Istvan Albert to get for.bam and rev.bam
	# https://www.biostars.org/p/92935/
	print "dataset is strand spec and paired end\n\n\n\n";
	
	# 1. alignments of the second in pair if they map to the forward strand
	# 2. alignments of the first in pair if they map to the reverse strand
	&runCmd("samtools view -b -f 163 $file >${baseName}_fwd1.bam");
	&runCmd("samtools index ${baseName}_fwd1.bam");
	
	&runCmd("samtools view -b -f 83 $file >${baseName}_fwd2.bam");
	&runCmd("samtools index ${baseName}_fwd2.bam");
	
	&runCmd("samtools merge -f ${baseName}.firststrand.bam ${baseName}_fwd1.bam ${baseName}_fwd2.bam");
	&runCmd("samtools index ${baseName}.firststrand.bam");
	
	# 1. alignments of the second in pair if they map to the reverse strand
	# 2. alignments of the first in pair if they map to the forward strand
	&runCmd("samtools view -b -f 147 $file > ${baseName}_rev1.bam");
	&runCmd("samtools index ${baseName}_rev1.bam");
	
	&runCmd("samtools view -b -f 99 $file > ${baseName}_rev2.bam");
	&runCmd("samtools index ${baseName}_rev2.bam");
	
	&runCmd("samtools merge -f ${baseName}.secondstrand.bam ${baseName}_rev1.bam ${baseName}_rev2.bam");
	&runCmd("samtools index ${baseName}.secondstrand.bam");
	
	&runCmd("bamutils tobedgraph ${baseName}.firststrand.bam >${baseName}.firststrand.bed");
	&runCmd("bamutils tobedgraph -minus ${baseName}.secondstrand.bam >${baseName}.secondstrand.bed");
	my $fwd = ${baseName}.".firststrand.bam";
	my $rev = ${baseName}.".secondstrand.bam";
	my $rev1 = ${baseName}."_rev1.bam";
	my $rev2 = ${baseName}."_rev2.bam";
	my $fwd1 = ${baseName}."_fwd1.bam";
	my $fwd2 = ${baseName}."_fwd2.bam";
	push @filesToDelete, ($fwd,$rev, $fwd1, $fwd2, $rev1, $rev2);
#	print "the long array is \n\n\n ";
#	print Dumper @filesToDelete;
	my@mapstat = &mapStats($mainResultsDir, $fwd, $totalReads);
	print M join("\t", @mapstat) . "\n";
        @mapstat = &mapStats($mainResultsDir, $rev, $totalReads);
	print M join("\t", @mapstat) . "\n";
	
    }
    else {
	print "dataset is not strand specific";
	&runCmd("samtools index $file");
	&runCmd("bamutils tobedgraph $file >${baseName}_sorted.bed");
	my @mapstat = &mapStats($mainResultsDir, $file, $totalReads);
	print M join("\t", @mapstat) . "\n";
	print "the file I am trying to print to M is $file\n";
    }
    &deleteIntermediateFiles(\@filesToDelete);
}


sub mapStats {
    my ($directory, $bamfile, $totalReads) = @_;
#    print "file running mapping stats on is $bamfile\n";

    my $coverage = CBIL::Util::DnaSeqMetrics::getCoverage($directory, $bamfile);

    my $statsHash = CBIL::Util::DnaSeqMetrics::runSamtoolsStats($bamfile);

    my $numberMapped = $statsHash->{'reads mapped'};
    my $percentMapped = $numberMapped / $totalReads;
    my $averageReadLength = $statsHash->{'average length'};

    return ($bamfile, $coverage, $percentMapped, $numberMapped, $averageReadLength);
}


sub deleteIntermediateFiles {
    my $array_ref =shift;
    foreach my $element (@$array_ref) {
	if (-e $element) {
	    my $cmd = "rm $element*";
	    print "$cmd\n";
	    &runCmd($cmd);
	}
	else {
	    next;
	}
	
    }
}
