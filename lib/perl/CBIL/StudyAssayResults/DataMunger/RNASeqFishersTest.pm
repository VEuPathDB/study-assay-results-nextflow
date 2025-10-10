package CBIL::StudyAssayResults::DataMunger::RNASeqFishersTest;
use base qw(CBIL::StudyAssayResults::DataMunger::TwoStateComparison Exporter);

use strict;

use CBIL::StudyAssayResults::Error;

use File::Temp qw/ tempfile /;

use Exporter;

my $MIN_DEPTH = 0;
my $MIN_MAX = 'min';

my $PROTOCOL_NAME = 'Fishers Test - RUM Output';
my $PROTOCOL_TYPE = 'unknown_protocol_type';

#-------------------------------------------------------------------------------

sub getMappingStatsFile1       { $_[0]->{mappingStatsFile1} }
sub setMappingStatsFile1       { $_[0]->{mappingStatsFile1} = $_[1]}

sub getMappingStatsFile2       { $_[0]->{mappingStatsFile2} }
sub setMappingStatsFile2       { $_[0]->{mappingStatsFile2} = $_[1]}

sub getCountsFile1             { $_[0]->{countsFile1} }
sub setCountsFile1             { $_[0]->{countsFile1} = $_[1] }

sub getCountsFile2             { $_[0]->{countsFile2} }
sub setCountsFile2             { $_[0]->{countsFile2} = $_[1] }

sub getSampleName1             { $_[0]->{sampleName1} }
sub setSampleName1             { $_[0]->{sampleName1} = $_[1] }

sub getSampleName2             { $_[0]->{sampleName2} }
sub setSampleName2             { $_[0]->{sampleName2} = $_[1] }

sub getIsPairedEnd             { $_[0]->{isPairedEnd} }

sub getMinDepth                { $_[0]->{minDepth} }
sub setMinDepth                { $_[0]->{minDepth} = $_[1] }

sub getMinMax                  { $_[0]->{minMax} }
sub setMinMax                  { $_[0]->{minMax} = $_[1] }

sub new {
  my ($class, $args) = @_;

  my $requiredParams = ['outputFile',
                        'mappingStatsFile1',
                        'mappingStatsFile2',
                        'countsFile1',
                        'countsFile2',
                        'isPairedEnd',
                       ];

  unless($args->{doNotLoad}) {
    push @$requiredParams, 'sampleName1';
    push @$requiredParams, 'sampleName2';
  }

  my $self = $class->SUPER::new($args, $requiredParams);

  unless(defined $self->getMinDepth()) {
    $self->setMinDepth($MIN_DEPTH);
  }

  unless(defined $self->getMinMax()) {
    $self->setMinMax($MIN_MAX);
  }

  my $isPairedEnd = $self->getIsPairedEnd();

  unless($self->getDoNotLoad()) {
    $self->setProtocolName($PROTOCOL_NAME);


    my $s1 = $self->getSampleName1();
    my $s2 = $self->getSampleName2();


    my $name = "$s1 vs $s2";
    my $protocolAppNodesHash = {$name => [$s1, $s2]};

    $self->setNames([$name]);
    $self->setFileNames([$name]);
    $self->setInputProtocolAppNodesHash($protocolAppNodesHash);
  }

  return $self;
}


sub findNumMappersFromMappingStatsFile {
  my ($self, $mapStatsFn) = @_;

  my $isPairedEnd = $self->getIsPairedEnd();

  my $fh = IO::File->new("<$mapStatsFn") || die "Cannot open mapping stats file:   $mapStatsFn\n";
  my $startRead = 0;
  my $value = 0;

  while (my $line=<$fh>) {
    if (($line =~ /^TOTAL/) && $isPairedEnd ){ 
      $startRead = 1;
    } elsif (($line =~ /^TOTAL:\s+(\S+)\s+\(/) && (!$isPairedEnd)){
      $value = $1;
      last;
    }
    if (($line =~ /one of forward or reverse mapped:\s+(\S+)\s+\(/) && ($startRead == 1)){
      $value = $1;
      last;
    }
  }

  $fh->close();

  $value =~ s/,//g;

  return $value;
}

sub readCountsFile {
  my ($self, $countsFile) = @_;

  my $minMax = $self->getMinMax();

  my $data = {};

  my $fh = IO::File->new("<$countsFile") || die "Cannot open file $countsFile\n";
  while (my $line=<$fh>) {
    if ($line !~ /^transcript/) {
      next;
    }
    chomp($line);
    my @arr = split(/\t/, $line);
    if ($minMax eq 'min') {
      $data->{$arr[6]}->{'count'} = $arr[2];
    }
    if ($minMax eq 'max') {
      $data->{$arr[6]}->{'count'} = $arr[2] + $arr[3];
    }
  }
  $fh->close();

  return $data;
}

sub makeTempROutputFile {
  my ($self, $tmpCountsFile, $tmpOutFile, $numMappers1, $numMappers2) = @_;

  my ($rFh, $rFile) = tempfile();

  my $rString = <<RString;
m<-function(c1,c2,n1,n2) {
   matrix(c(c1,c2,n1-c1,n2-c2),nrow=2,byrow=F)
}

inputFile="$tmpCountsFile";
outputFile="$tmpOutFile";
n1=$numMappers1;
n2=$numMappers2;

data <- as.matrix(read.table(inputFile, header=F))
p<-numeric()
for (i in 1:nrow(data)) {
   if ((data[i,1]/n1)>=(data[i,2]/n2)){
      p[i]<-fisher.test(m(data[i,1],data[i,2],n1,n2),alternative="greater")\$p
   }
   else {
      p[i]<-fisher.test(m(data[i,1],data[i,2],n1,n2),alternative="less")\$p
   }	
}
write.table(p, file=outputFile, col.names=F, row.names=F, sep="\\t", eol="\n", quote=F)
quit("no");
RString


  print $rFh $rString;
  close $rFh;

  return $rFile;
}



sub munge {
  my ($self) = @_;

  my $outputFile = $self->getOutputFile();
  my $minDepth = $self->getMinDepth();

  my $mappingStatsFile1 = $self->getMappingStatsFile1();
  my $mappingStatsFile2 = $self->getMappingStatsFile2();

  my $numMappers1 = $self->findNumMappersFromMappingStatsFile($mappingStatsFile1);
  my $numMappers2 = $self->findNumMappersFromMappingStatsFile($mappingStatsFile2);

#  STDOUT->print("n1=$numMappers1\n");
#  STDOUT->print("n2=$numMappers2\n");

  if($numMappers1 == 0 || $numMappers2 == 0) {
    CBIL::StudyAssayResults::Error->new("Error reading the mappingStats file to find the numMappers. (perhaps isPairedEnd is set incorrectly??)")->throw();    
  }

  my $countsFile1 = $self->getCountsFile1();

  my $countsFile2 = $self->getCountsFile2();

  my $data1 = $self->readCountsFile($countsFile1);
  my $data2 = $self->readCountsFile($countsFile2);

  my ($countsTmpFh, $countsTmpFn) = tempfile();
  my ($tmpRFh, $tmpOutFile) = tempfile();
  close $tmpOutFile; # I only need the tmp file name for this

  foreach my $id (sort keys(%{$data1})) {
    $countsTmpFh->print("$data1->{$id}->{'count'}\t$data2->{$id}->{'count'}\n");
  }
  close $countsTmpFh;

  my $rFile = $self->makeTempROutputFile($countsTmpFn, $tmpOutFile, $numMappers1, $numMappers2);

  $self->runR($rFile);

  my %p;
  my $fh = IO::File->new("<$tmpOutFile");
  my $i = 0;
  my @ids = sort keys(%{$data1});
  while (my $line=<$fh>) {
    chomp($line);
    $p{$ids[$i]} = $line;
    $i++;
  }
  $fh->close();

  my $wfh1 = IO::File->new("> $outputFile");
  $wfh1->print("row_id\tpvalue_mant\tpvalue_exp\n");

  foreach my $id (sort { $p{$a} <=> $p{$b} } keys %{$data1}) {
    if ($data1->{$id}->{'count'} >= $minDepth || $data2->{$id}->{'count'} >= $minDepth) {

      my @valueSplit = split(/e/, $p{$id});

      $valueSplit[1] = $valueSplit[1] ? $valueSplit[1]:0;

      my $string = "$id\t$valueSplit[0]\t$valueSplit[1]\n";

      $wfh1->print($string);
  }
  }
  $wfh1->close();

  $self->createConfigFile();

  unlink($rFile, $countsTmpFn, $tmpOutFile);
}

1;
