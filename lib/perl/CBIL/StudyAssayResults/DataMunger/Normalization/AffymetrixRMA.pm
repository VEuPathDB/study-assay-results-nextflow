package CBIL::StudyAssayResults::DataMunger::Normalization::AffymetrixRMA;
use base qw(CBIL::StudyAssayResults::DataMunger::Normalization);

use strict;

use File::Basename;

use Cwd;

sub getCdfFile                 { $_[0]->getMappingFile }
sub getCelFilePath             { $_[0]->getMainDirectory }

sub munge {
  my ($self) = @_;

  my $dir = getcwd();

  my $rTempPackageDir = "/tmp/RtempPackage";
  mkdir $rTempPackageDir;
  chdir $rTempPackageDir;

  my $cdfFile = $self->getCdfFile();
  my $cdfFileBasename = basename($cdfFile);
  my $cleanCdfName = $cdfFileBasename;
  $cleanCdfName =~  tr/[A-Z]/[a-z]/;
  $cleanCdfName =~ s/[_\- ]//g;
  $cleanCdfName =~ s/\.//i;

  my $dataFilesRString = $self->makeDataFilesRString();

  my $makeCdfPackageRFile = $self->writeCdfPackage($rTempPackageDir);
  $self->runR($makeCdfPackageRFile);

  my $buildCmd = "R CMD build $cleanCdfName";
  my $buildRes = system($buildCmd);
  unless($buildRes / 256 == 0) {
    CBIL::StudyAssayResults::Error->new("Error while attempting to run R\n$buildCmd")->throw();
  }

  my $installCmd = "R CMD INSTALL $cleanCdfName" . "*.tar.gz -l $rTempPackageDir";
  my $installRes = system($installCmd);
  unless($installRes / 256 == 0) {
    CBIL::StudyAssayResults::Error->new("Error while attempting to run R:\n$installCmd")->throw();
  }

  my $rFile = $self->writeRScript($dataFilesRString, $cleanCdfName, $rTempPackageDir);

  $self->runR($rFile);

  chdir $dir;

  unlink($rFile, $makeCdfPackageRFile);
  system("rm -rf $rTempPackageDir");
}


sub writeCdfPackage {
  my ($self, $pkgPath) = @_;

  my $compress = "FALSE";
  if($self->isMappingFileZipped()) {
    $compress = "TRUE";
  }

  my $cdfFile = $self->getCdfFile();
  my $cdfFileBasename = basename($cdfFile);
  my $cdfFileDirname = dirname($cdfFile);

  my $rFile = "/tmp/$cdfFileBasename.R";

  open(RCODE, "> $rFile") or die "Cannot open $rFile for writing:$!";

  my $rString = <<RString;
load.makecdfenv = library(makecdfenv, logical.return=TRUE)

if(load.makecdfenv) {
  pkgpath = "$pkgPath";
  my.cdf <- make.cdf.package("$cdfFileBasename", species="Who_cares", cdf.path="$cdfFileDirname", package.path =pkgpath, compress=$compress, unlink=TRUE);
} else {
  stop("ERROR:  could not load required libraries makecdfenv");
}
RString

  print RCODE $rString;

  close RCODE;

  return $rFile;
}

sub writeRScript {
  my ($self, $samples, $cdfLibrary, $rTempPackageDir) = @_;

  my $celFilePath = $self->getCelFilePath();

  my $cdfFile = $self->getCdfFile();
  my $cdfFileBasename = basename($cdfFile);

  my $outputFile = $celFilePath . "/" . $self->getOutputFile();
  my $outputFileBase = basename($outputFile);
  my $rFile = "/tmp/$outputFileBase.R";

  open(RCODE, "> $rFile") or die "Cannot open $rFile for writing:$!";

  my $rString = <<RString;

.libPaths("$rTempPackageDir")
load.affy = library(affy, logical.return=TRUE);
load.cdf = library($cdfLibrary, logical.return=TRUE);

if(load.affy && load.cdf) {

  data.files = vector();
  $samples

  dat = ReadAffy(filenames=data.files, cdfname="$cdfLibrary", celfile.path="$celFilePath")
  res = rma(dat)

  colnames(exprs(res)) = data.files;

  write.table(exprs(res), file="$outputFile",quote=F,sep="\\t", row.names=TRUE, col.names=NA);

} else {
  stop("ERROR:  could not load required libraries affy and $cdfLibrary");
}

RString


  print RCODE $rString;

  close RCODE;

  return $rFile;
}




1;
