=head1 NAME

ApiCommonData::Load::IterativeWGCNAResults - Processes RNA-Seq data through iterative WGCNA pipeline

=head1 SYNOPSIS

  my $wgcna = ApiCommonData::Load::IterativeWGCNAResults->new({
    mainDirectory => '/path/to/data',
    inputFile => 'expression_matrix.txt',
    softThresholdPower => 6,
    threshold => 1.0,
    profileSetName => 'MyStudy',
    ...
  });

  $wgcna->munge();

=head1 DESCRIPTION

This module performs Weighted Gene Co-expression Network Analysis (WGCNA) on RNA-Seq
expression data. It processes input expression matrices by filtering low-expressed genes
and pseudogenes, runs the iterativeWGCNA algorithm, and organizes the results into
module membership files and eigengene profiles for database loading.

The analysis workflow:
1. Loads a list of pseudogenes to exclude
2. Preprocesses input data by filtering genes below expression thresholds
3. Executes the iterativeWGCNA algorithm with specified parameters
4. Parses module membership correlations and writes per-module files
5. Processes module eigengenes for downstream analysis

Currently only analyzes the first strand and excludes pseudogenes.

=head1 AUTHOR

VEuPathDB

=cut

package ApiCommonData::Load::IterativeWGCNAResults;
use base qw(CBIL::StudyAssayResults::DataMunger::Loadable);

use strict;
use warnings;
use CBIL::StudyAssayResults::DataMunger::NoSampleConfigurationProfiles;

use Data::Dumper;

use Time::Piece;

# Constants
use constant {
    STRAND => 'firststrand',
    SAMPLES_PASSING_THRESHOLD_PCT => 0.9,
    MERGE_CUT_HEIGHT => 0.25,
    WGCNA_PARAMS => 'maxBlockSize=3000,networkType=signed,minModuleSize=10,reassignThreshold=0,minKMEtoStay=0.8,minCoreKME=0.8',
    OUTPUT_DIR => 'FirstStrandOutputs',
    MM_OUTPUT_DIR => 'FirstStrandMMResultsForLoading',
    EIGENGENES_SUFFIX => '_1stStrand.txt',
};

# Accessor methods
sub getPower        { $_[0]->{softThresholdPower} }
sub getOrganismAbbrev        { $_[0]->{organismAbbrev} }
sub getInputSuffixMM              { $_[0]->{inputSuffixMM} }
sub getInputSuffixME              { $_[0]->{inputSuffixME} }
sub getInputSampleSuffix              { $_[0]->{inputSampleSuffix} }
sub getInputFile              { $_[0]->{inputFile} }
sub getprofileSetName              { $_[0]->{profileSetName} }
sub getTechnologyType              { $_[0]->{technologyType} }
sub getThreshold              { $_[0]->{threshold} }
sub getValueType              { $_[0]->{valueType} }
sub getQuantificationType              { $_[0]->{quantificationType} }
sub getSamples                 { $_[0]->{samples} }

#-------------------------------------------------------------------------------
sub new {
  my ($class, $args) = @_; 
  $args->{sourceIdType} = "gene";

  # update main directory to new data structure
  # cannot update arg at command line because it is correct for RnaSeqAnalysis Module
  my $mainDirectory = $args->{mainDirectory};
  if(-e "${mainDirectory}/analysis_output") {
	  $mainDirectory = "${mainDirectory}/analysis_output";
  }

  $args->{mainDirectory} = $mainDirectory;

  my $self = $class->SUPER::new($args) ;          
  
  return $self;
}

#-------------------------------------------------------------------------------
# Main analysis method - orchestrates the WGCNA analysis workflow
#-------------------------------------------------------------------------------
sub munge {
    my ($self) = @_;

    my $mainDirectory = $self->getMainDirectory();
    my $profileSetName = $self->getprofileSetName();

    # Load pseudogenes list
    my $pseudogenes = $self->_loadPseudogenes();

    # Preprocess input file and get sample names
    print STDERR "Using the first strand and excluding pseudogenes\n";
    my ($preprocessedFile, $inputSamples) = $self->_preprocessInputFile($pseudogenes);

    # Run WGCNA analysis
    my $outputDirFullPath = $self->_runWGCNAAnalysis($preprocessedFile);

    # Process module eigengenes
    my $eigengeneNameHash = $self->_processModuleEigengenes($outputDirFullPath, $mainDirectory, $profileSetName);
    
    # Parse and save module membership results
    my ($modules, $files) = $self->_parseModuleMembership($outputDirFullPath, $eigengeneNameHash);

    # Configure module membership for loading
    $self->_configureModuleMembership($modules, $files, $inputSamples, $profileSetName);

}

#-------------------------------------------------------------------------------
# Load pseudogenes from file into a hash
#-------------------------------------------------------------------------------
sub _loadPseudogenes {
    my ($self) = @_;

    my $pseudogenesFile = $self->getPseudogenesFile();
    open(my $fh, '<', $pseudogenesFile)
        or die "Cannot open $pseudogenesFile for reading: $!";

    my %pseudogenes;
    while (my $line = <$fh>) {
        chomp $line;
        $pseudogenes{$line} = 1;
    }
    close $fh;

    return \%pseudogenes;
}

#-------------------------------------------------------------------------------
# Preprocess input file: filter genes by threshold and exclude pseudogenes
#-------------------------------------------------------------------------------
sub _preprocessInputFile {
    my ($self, $pseudogenes) = @_;

    my $mainDirectory = $self->getMainDirectory();
    my $inputFile = $self->getInputFile();
    my $threshold = $self->getThreshold();
    my $preprocessedFile = "Preprocessed_" . $inputFile;

   if (!defined $self->{samples} || ref($self->{samples}) ne 'ARRAY' || !@{$self->{samples}}) {
        warn "INFO: \$self->{samples} is empty. Populating from input file header...\n";
        open(my $fh, '<', "$mainDirectory/$inputFile")
            or die "Cannot open $mainDirectory/$inputFile: $!";
        my $headerLine = <$fh>;
        close $fh;
        chomp $headerLine;
        my @headers = split("\t", $headerLine);
        @headers = grep { $_ ne '' } @headers;
        $self->{samples} = \@headers;
    }

    my $samplesHash = $self->groupListHashRef($self->getSamples());
    open(my $in, '<', "$mainDirectory/$inputFile")
        or die "Couldn't open file $mainDirectory/$inputFile for reading: $!";
    open(my $out, '>', "$mainDirectory/$preprocessedFile")
        or die "Couldn't open file $mainDirectory/$preprocessedFile for writing: $!";
    my %inputSamples;

    while (my $line = <$in>) {
        chomp $line;
        if ($. == 1) {
            # Process header line
            my @headers = split("\t", $line);

            my @origHeaders;
            push @origHeaders, shift(@headers);

            foreach my $header (@headers) {

                die "Require 1:1 sample name mapping". Dumper $samplesHash unless(scalar @{$samplesHash->{$header}} == 1);
                my $origName = $samplesHash->{$header}->[0];
                push @origHeaders, $origName;
            }

            print $out join("\t", @origHeaders) . "\n";

        } else {
            # Process data lines
            my @geneLine = split("\t", $line);
            my $geneId = $geneLine[0];

            # Count samples passing threshold
            my $countPassing = grep { $_ > $threshold } @geneLine[1 .. $#geneLine];
            my $passingPct = $countPassing / $#geneLine;

            if ($passingPct > SAMPLES_PASSING_THRESHOLD_PCT) {
                unless ($pseudogenes->{$geneId}) {
                    print $out join("\t", @geneLine) . "\n";
                }
            } else {
                print STDERR "$geneId had only $countPassing of $#geneLine samples passing the threshold, " .
                      "so $geneId will not be included in the analysis.\n";
            }
        }
    }

    close $in;
    close $out;

    return ($preprocessedFile, \%inputSamples);
}

#-------------------------------------------------------------------------------
# Run the iterativeWGCNA analysis
#-------------------------------------------------------------------------------
sub _runWGCNAAnalysis {
    my ($self, $preprocessedFile) = @_;

    my $mainDirectory = $self->getMainDirectory();
    my $power = $self->getPower();
    my $outputDir = OUTPUT_DIR;
    my $outputDirFullPath = "$mainDirectory/$outputDir";

    mkdir($outputDirFullPath)
        or die "Cannot create directory $outputDirFullPath: $!";

    my $inputFileForWGCNA = "$mainDirectory/$preprocessedFile";
    my $mergeCutHeight = MERGE_CUT_HEIGHT;
    my $wgcnaParams = WGCNA_PARAMS;

    # Build command with power parameter substituted
    my $command = "iterativeWGCNA -i $inputFileForWGCNA -o $outputDirFullPath -v " .
                  "--wgcnaParameters $wgcnaParams,power=$power " .
                  "--finalMergeCutHeight $mergeCutHeight";

    print STDERR "INPUT FILE: $inputFileForWGCNA\n";

    system($command) == 0
        or die "Error running WGCNA command: $command";

    return $outputDirFullPath;
}

#-------------------------------------------------------------------------------
# Parse module membership results and create output files
#-------------------------------------------------------------------------------
sub _parseModuleMembership {
    my ($self, $outputDirFullPath, $eigengeneNameHash) = @_;

    my $mergeCutHeight = MERGE_CUT_HEIGHT;
    my $membershipFile = "$outputDirFullPath/merged-$mergeCutHeight-membership.txt";
    my $outputDirMM = MM_OUTPUT_DIR;
    my $outputDirMMFullPath = "$outputDirFullPath/$outputDirMM";

    mkdir($outputDirMMFullPath)
        or die "Cannot create directory $outputDirMMFullPath: $!";

    # Parse membership file
    open(my $mm, '<', $membershipFile)
        or die "Couldn't open $membershipFile for reading: $!";

    my %mmHash;
    <$mm>; # Skip header

    while (my $line = <$mm>) {
        chomp $line;

        my @fields = split /\t/, $line;

        my $moduleName = $eigengeneNameHash->{$fields[1]} ? $eigengeneNameHash->{$fields[1]} : $fields[1];

        push @{$mmHash{$moduleName}}, "$fields[0]\t$fields[2]\n";
    }
    close $mm;

    # Write per-module membership files
    my @files;
    my @modules;
    my @moduleNames = grep { $_ ne 'UNCLASSIFIED' } keys %mmHash;

    foreach my $moduleName (@moduleNames) {
        push @modules, $moduleName . " " . $self->getInputSuffixMM();
        push @files, OUTPUT_DIR . "/$outputDirMM/$moduleName" . "_1st.txt";

        my $outputFile = "$outputDirMMFullPath/$moduleName" . "_1st.txt";
        open(my $mmout, '>', $outputFile) or die "Cannot open $outputFile: $!";
        print $mmout "geneID\tcorrelation_coefficient\n";
        print $mmout $_ for @{$mmHash{$moduleName}};
        close $mmout;
    }

    return (\@modules, \@files);
}

#-------------------------------------------------------------------------------
# Configure module membership results for loading
#-------------------------------------------------------------------------------
sub _configureModuleMembership {
    my ($self, $modules, $files, $inputSamples, $profileSetName) = @_;

    my %inputProtocolAppNodesHash;
    foreach my $module (@$modules) {
        my @sampleList = map { $_ . " " . $self->getInputSampleSuffix() }
                         sort keys %$inputSamples;
        push @{$inputProtocolAppNodesHash{$module}}, join(';', @sampleList);
    }

    $self->setInputProtocolAppNodesHash(\%inputProtocolAppNodesHash);
    $self->setNames($modules);
    $self->setFileNames($files);
    $self->setProtocolName("WGCNA");
    $self->setSourceIdType("gene");
    $self->setProfileSetName("$profileSetName " . $self->getInputSuffixMM());
    $self->createConfigFile();
}

#-------------------------------------------------------------------------------
# Process module eigengenes for loading
#-------------------------------------------------------------------------------
sub _processModuleEigengenes {
    my ($self, $outputDirFullPath, $mainDirectory, $profileSetName) = @_;

    my $quantificationType = $self->getQuantificationType();
    my $valueType = $self->getValueType();
    my $strand = STRAND;
    my $mergeCutHeight = MERGE_CUT_HEIGHT;
    my $eigengenesFile = "merged-$mergeCutHeight-eigengenes" . EIGENGENES_SUFFIX;

    my $orgAbbrev = $self->getOrganismAbbrev();
    my $t = localtime;  # gets current local time
    my $formatted_date = $t->strftime('%d%b%Y');  # formats date as 05Aug2025


    # Copy and rename eigengenes file
    my $sourceFile = "$outputDirFullPath/merged-$mergeCutHeight-eigengenes.txt";
    open(IN, $sourceFile) or die "Cannot open sourceFile $sourceFile for reading: $!";
    open(OUT, ">$eigengenesFile") or die "Cannot open eigengenesFile $eigengenesFile for writing: $!";

    my $header = <IN>;
    print OUT $header;

    my %moduleMap;

    my $moduleCount = 1;
    while(<IN>) {
        chomp;
        my @a = split(/\t/, $_);

        my $newId = "Module_${moduleCount}_${formatted_date}_${orgAbbrev}";

        $moduleMap{$a[0]} = $newId;
        $a[0] = $newId;

        print OUT join("\t", @a) . "\n";
        
        $moduleCount++;
    }

    close IN;
    close OUT;
    
    return \%moduleMap;

    # my $cpCommand = "cp $sourceFile $eigengenesFile";
    # system($cpCommand) == 0
    #     or die "Error copying eigengenes file: $!";

    # # Create eigengenes profile object
    # my $egenes = CBIL::StudyAssayResults::DataMunger::NoSampleConfigurationProfiles->new({
    #     mainDirectory => $mainDirectory,
    #     inputFile => $eigengenesFile,
    #     makePercentiles => 0,
    #     doNotLoad => 1,
    #     profileSetName => $profileSetName
    # });

    # $egenes->setTechnologyType("RNASeq");
    # $egenes->setDisplaySuffix(" [$quantificationType - $strand - $valueType - unique]");
    # $egenes->setProtocolName("wgcna_eigengene");
    # $egenes->setSourceIdType("module");

    #$egenes->munge();
}



1;

