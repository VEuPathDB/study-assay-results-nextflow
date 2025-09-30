package CBIL::StudyAssayResults::DataMunger;

use strict;

use Tie::IxHash;

use CBIL::StudyAssayResults::Error;
use CBIL::StudyAssayResults::Utils;

use File::Basename;
use File::Temp qw/ tempfile /;

#--------------------------------------------------------------------------------

sub getOutputFile           { $_[0]->{outputFile} }
sub setOutputFile           { $_[0]->{outputFile} = $_[1] }

sub getInputFile            { $_[0]->{inputFile} }
sub setInputFile            { $_[0]->{inputFile} = $_[1] }

sub getFileSuffix           { $_[0]->{fileSuffix} }
sub setFileSuffix           { $_[0]->{fileSuffix} = $_[1] }

sub getMainDirectory        { $_[0]->{mainDirectory} }
sub setMainDirectory        { $_[0]->{mainDirectory} = $_[1] }

sub getChecker              { $_[0]->{_checker} }
sub setChecker { 
  my ($self, $checker) = @_;

  $checker->check();

  $self->{_checker} = $checker;
}

sub getDataFiles               { $_[0]->{dataFiles} }
sub inputFileIsMappingFile     { $_[0]->{inputFileIsMappingFile} }

sub getMappingFileOligoColumn  { $_[0]->{mappingFileOligoColumn} }
sub setMappingFileOligoColumn  { $_[0]->{mappingFileOligoColumn} = $_[1] }

sub getMappingFileGeneColumn   { $_[0]->{mappingFileGeneColumn} }
sub setMappingFileGeneColumn   { $_[0]->{mappingFileGeneColumn} = $_[1] }

sub getMappingFileHasHeader    { $_[0]->{mappingFileHasHeader} }
sub setMappingFileHasHeader    { $_[0]->{mappingFileHasHeader} = $_[1] }

sub getTechnologyType          { $_[0]->{_technology_type} }
sub setTechnologyType          { $_[0]->{_technology_type} = $_[1] }

#--------------------------------------------------------------------------------

my $MAP_HAS_HEADER = 0;
my $MAP_GENE_COL = 'first';
my $MAP_OLIGO_COL = 'second';

#--------------------------------------------------------------------------------

sub new {
  my ($class, $args, $requiredParamArrayRef) = @_;

  if(my $mainDirectory = $args->{mainDirectory}) {
    chdir $mainDirectory;
  }
  else {
    CBIL::StudyAssayResults::Error->new("Main Directory was not provided")->throw();
  }

  if(ref($class) eq 'CBIL::StudyAssayResults::DataMunger') {
    CBIL::StudyAssayResults::Error->
        new("try to instantiate an abstract class:  $class")->throw();
  }

  CBIL::StudyAssayResults::Utils::checkRequiredParams($requiredParamArrayRef, $args);

  my $self=bless $args, $class;

  $self->setMappingFileOligoColumn($MAP_OLIGO_COL) unless(defined $self->getMappingFileOligoColumn());
  $self->setMappingFileGeneColumn($MAP_GENE_COL) unless(defined $self->getMappingFileGeneColumn());
  $self->setMappingFileHasHeader($MAP_HAS_HEADER) unless(defined $self->getMappingFileHasHeader());

  return $self;
}

#-------------------------------------------------------------------------------

sub munge {
  die "no munge method defined for subclass"
}

#-------------------------------------------------------------------------------

sub runR {
  my ($self, $script) = @_;

  my $command = "cat $script  | R --no-save ";

  my $systemResult = system($command);

  unless($systemResult / 256 == 0) {
    CBIL::StudyAssayResults::Error->new("Error while attempting to run R:\n$command")->throw();
  }
}

#-------------------------------------------------------------------------------

sub groupListHashRef {
  my ($self, $paramValueString) = @_;

  my %rv;
  tie %rv, "Tie::IxHash";

  return \%rv unless($paramValueString);

  unless(ref($paramValueString) eq 'ARRAY') {
    die "Illegal param to method call [groupListParam].  Expected ARRAYREF";
  }

  foreach my $groupSample (@$paramValueString) {
    my ($group, $sample) = split(/\|/, $groupSample);

    $sample = $group if (! $sample);  # if group name is not specified; can be used when group has just 1 sample
    push @{$rv{$group}}, $sample;
  }

  return \%rv;
}


#-------------------------------------------------------------------------------

sub mappingFileForR {
  my ($self, $idArray) = @_;

  my ($fh, $filename) = tempfile();

  my $mappingFile = $self->getMappingFile();

  my $oligoColumn = $self->getMappingFileOligoColumn();

  my $oligoIndex = $oligoColumn eq 'first' ? 0 : 1;
  my $geneIndex = $oligoColumn eq 'first' ? 1 : 0;

  open(MAP, $mappingFile) or die "Cannot open file $mappingFile for reading: $!";

  # remove the first line if there is a header
  <MAP> if($self->getMappingFileHasHeader() == 1);

  my %oligoToGene;

  while(<MAP>) {
    chomp;
    my @cols = split(/\t/, $_);

    my $oligoString = $cols[$oligoIndex];
    my $geneString = $cols[$geneIndex];

    my @oligos = split(',', $oligoString);
    my @genes =  split(',', $geneString);

    foreach my $oligo (@oligos) {
      my @seenGenes;
      @seenGenes = @{$oligoToGene{$oligo}} if($oligoToGene{$oligo});

      foreach my $gene (@genes) {
        next if(&alreadyExists($gene, \@seenGenes));
        push @{$oligoToGene{$oligo}}, $gene;
      }
    }
  }
  print $fh "ID\tGENES\n";
  foreach my $oligo (@$idArray) {
    my @genes;
    @genes = @{$oligoToGene{$oligo}} if($oligoToGene{$oligo});
    my $genesString = join(',', @genes);

    print $fh "$oligo\t$genesString\n";
  }

  close $fh;

  return $filename;

}

#-------------------------------------------------------------------------------
# static method
sub alreadyExists {
  my ($val, $ar) = @_;

  foreach(@$ar) {
    return 1 if($_ eq $val);
  }
  return 0;
}

#-------------------------------------------------------------------------------

sub getMappingFile          { 
  my ($self) = @_;

  if($self->inputFileIsMappingFile()) {
    return $self->{inputFile};
  }

  return $self->{mappingFile};
}


sub clone {
  my $self = shift;
  my $copy = { %$self };
  bless $copy, ref $self;
} 


sub readInputFileHeaderAsSamples {
  my ($self) = @_;

  my $fn = $self->getInputFile();

  return $self->readFileHeaderAsSamples($fn);
}

sub readFileHeaderAsSamples {
  my ($self, $fn) = @_;

  open(FILE, $fn) or die "Cannot open file $fn for reading: $!";

  my $header = <FILE>;
  chomp $header;
  close FILE;

  my @vals = split(/\t/, $header);
  
  # remove the row header column;
  shift @vals;

  return \@vals;
}




1;
