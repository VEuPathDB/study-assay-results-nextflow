package CBIL::StudyAssayResults::DataMunger::SplineSmoothing;
use base qw(CBIL::StudyAssayResults::DataMunger::Profiles);

use strict;

use Data::Dumper;

use File::Temp qw/ tempfile /;

use CBIL::StudyAssayResults::Error;

#-------------------------------------------------------------------------------

sub getInterpolationN { $_[0]->{interpolation_n} }
sub setInterpolationN { $_[0]->{interpolation_n} = $_[1] }

sub getSplineDF       { $_[0]->{degrees_of_freedom} }
sub setSplineDF       { $_[0]->{degrees_of_freedom} = $_[1] }

#-------------------------------------------------------------------------------

sub new {
  my ($class, $args) = @_;

  $args->{samples} = 'PLACEHOLDER';

  my $self = $class->SUPER::new($args);

  return $self;
}


#-------------------------------------------------------------------------------

sub munge {
  my ($self) = @_;

  my ($splinesFile, $interpFile, $rFile) = $self->writeRFile();

  my $splineSamples = $self->readFileHeaderAsSamplesWithSuffix($splinesFile, "spline smoothed");

  $self->setSamples($splineSamples);
  $self->setInputFile($splinesFile);

  $self->SUPER::munge();

  my $interpN = $self->getInterpolationN();
  if(defined $interpN) {
    $self->addProtocolParamValue("interpolationN", $interpN);

    my $interpSamples = $self->readFileHeaderAsSamples($interpFile);

    $self->setSamples($interpSamples);
    $self->setInputFile($interpFile);

    my $outputFile = $self->getOutputFile() . "_" . $interpN;
    $self->setOutputFile($outputFile);

    $self->setProtocolName($self->getProtocolName() . " - Interpolation");

    $self->SUPER::munge();

    unlink($interpFile);
  }

  unlink($rFile, $splinesFile);
}

#-------------------------------------------------------------------------------

sub readFileHeaderAsSamplesWithSuffix {
  my ($self, $fn, $append) = @_;

  my $samples = $self->readFileHeaderAsSamples($fn);

    my @rv = map { $_ . " - $append|$_" } @$samples;
    return \@rv;
}

#-------------------------------------------------------------------------------


sub writeRFile {
  my ($self) = @_;

  my ($outputFh, $outputFile) = tempfile();

  my $inputFile = $self->getInputFile();
  my $interpN = $self->getInterpolationN();
  my $df = $self->getSplineDF();

  my $dfString = ", df=$df";
  $df = defined($df) ? $dfString : "";

  my $doInterp = 'FALSE';
  my $interpFile;
  if(defined($interpN)) {
    $doInterp = 'TRUE';

    $interpFile = "$outputFile" . "_" . $interpN;
  }


  my ($fh, $file) = tempfile();



 my $rString = <<RString;
dat = read.table("$inputFile", header=T, sep="\\t", check.names=FALSE);
numHeader = as.numeric(sub(" *[a-z-A-Z]+ *", "", colnames(dat), perl=T));

ids = as.character(dat[,1]);

newHeader = vector();
newDat = vector();
xCoords = vector();

for(i in 2:length(numHeader)) {
 if(!is.na(numHeader[i])) {
    newDat = cbind(newDat, dat[,i]);
    newHeader[length(newHeader)+1] = colnames(dat)[i]; 
    xCoords[length(xCoords)+1] = numHeader[i]; 
  }
}

colnames(newDat) = newHeader;


splines = vector();
interpolatedSplines = vector();

predictX = round(approx(xCoords, n=$interpN)\$y, 1);


for(i in 1:nrow(newDat)) {
#Case 1 - all values are NA : 
#Case 2 - no values are NA :
#Case 3 - one or more values are NA, but not all :
  if (sum(is.na(newDat[i,])) == length(newDat[i,]))  {
    splines = rbind(splines, newDat[i,]);
  }
  else if(sum(is.na(newDat[i,])) == 0 ) {
    spline = smooth.spline(xCoords, newDat[i,]$df);
    splines = rbind(splines, spline\$y);
  }
  else {
    approxY =approx(newDat[i,], n=length(newDat[i,]))\$y;
    spline = smooth.spline(xCoords, approxY$df);
    splines = rbind(splines, spline\$y);
  }
  if($doInterp) {
    if (sum(is.na(newDat[i,])) == length(newDat[i,] )) {
      interpolatedSplines = rbind(interpolatedSplines, (predictX * NA));
    }
    else {
      interpolatedSplines = rbind(interpolatedSplines, predict(spline, predictX)\$y);
     }
   }
}

colnames(splines) = as.character(newHeader);
colnames(interpolatedSplines) = as.character(predictX);

write.table(splines, file="$outputFile", quote=FALSE,sep="\\t", row.names=ids, col.names=NA);

if($doInterp) {
  write.table(interpolatedSplines, file="$interpFile", quote=FALSE, sep="\\t", row.names=ids, col.names=NA);
}

RString


  print $fh $rString;

  close $fh;


  $self->runR($file);

  return $outputFile, $interpFile, $file;
}
1;
