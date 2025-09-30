package CBIL::StudyAssayResults::Check::ConsistentIdOrder;
use base qw(CBIL::StudyAssayResults::Check);

use strict;

use CBIL::StudyAssayResults::Utils;
use CBIL::StudyAssayResults::Error;

sub getDataDirPath     { $_[0]->{_data_dir_path} }
sub setDataDirPath     { $_[0]->{_data_dir_path} = $_[1] }

sub getDataFiles      { $_[0]->{_data_files} }
sub setDataFiles      { $_[0]->{_data_files} = $_[1] }

sub getIdColumnName   { $_[0]->{_id_column_names} }
sub setIdColumnName   { $_[0]->{_id_column_names} = $_[1] }

sub getIdArray        { $_[0]->{_id_array} }
sub setIdArray        { $_[0]->{_id_array} = $_[1] }

sub new {
  my ($class, $dataFiles, $pathToDataFiles, $idColName) = @_;

  my $self = bless {}, $class;

  $self->setDataDirPath($pathToDataFiles);
  $self->setDataFiles($dataFiles);
  $self->setIdColumnName($idColName);

  return $self;
}


sub check {
  my ($self) = @_;

  my $del = qr/\t/;

  my $idColName = $self->getIdColumnName();

  my $dataFiles = $self->getDataFiles();
  my $dirPath = $self->getDataDirPath();

  my $firstDataFile = $dataFiles->[0];
  my $firstDataFilePath = $dirPath . "/" . $firstDataFile;

  my $idArray = $self->readColumn($firstDataFilePath, $idColName, $del);
  $self->setIdArray($idArray);

  foreach my $file (@$dataFiles) {
    my $fullFilePath = $dirPath . "/" . $file;

    my $dataFileOrder = $self->readColumn($fullFilePath, $idColName, $del);

    $self->compare($idArray, $dataFileOrder);
  }
  return 1;
}

sub compare {
  my ($self, $array1, $array2) = @_;

  unless(scalar @$array1 == scalar @$array2) {
    CBIL::StudyAssayResults::Error->new("Data files have different number of lines than mapping file")->throw();
  }

  for(my $i = 0; $i < scalar @$array1; $i++) {

    unless($array1->[$i] eq $array2->[$i]) {
      print STDERR $array1->[$i] . "\t" . $array2->[$i] . "\n";
      CBIL::StudyAssayResults::Error->new("Identifiers must be in the same order in the mapping file as in data files")->throw();
    }
  }
}

sub readColumn {
  my ($self, $file, $colName, $del) = @_;

  my @res;

  open(FILE, $file) or die "Cannot open file $file for reading: $!";

  my $header = <FILE>;
  chomp($header);

  my $headerIndexHash = CBIL::StudyAssayResults::Utils::headerIndexHashRef($header, $del);

  my $idIndex = $headerIndexHash->{$colName};

  while(<FILE>) {
    chomp;

    my @a = split($del, $_);

    my $value = $a[$idIndex];

    $value =~ s/\"//g;

    push @res, $value;
  }

  close FILE;

  return \@res;
}



1;
