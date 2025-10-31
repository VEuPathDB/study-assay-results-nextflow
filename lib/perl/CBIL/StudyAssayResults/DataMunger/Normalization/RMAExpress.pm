package CBIL::StudyAssayResults::DataMunger::Normalization::RMAExpress;
use base qw(CBIL::StudyAssayResults::DataMunger::Normalization);

use strict;

use CBIL::StudyAssayResults::Error;
use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Cwd;

sub getCdfFile                 { $_[0]->getMappingFile }
sub getCelFilePath             { $_[0]->getMainDirectory }

sub munge {
  my ($self) = @_;

  my $dir = getcwd();

  my $rTempPackageDir = tempdir( CLEANUP => 1 );
  mkdir $rTempPackageDir;
  chdir $rTempPackageDir;

  my $dataFilesRString = $self->makeDataFilesRString();

  # Get the clean CDF name that was created
  my $cdfFile = $self->getCdfFile();
  my $cdfFileBasename = basename($cdfFile);
  my $cleanCdfName = $self->getCleanCdfName($cdfFileBasename);

  my $makeCdfPackageRFile = $self->writeCdfPackage($rTempPackageDir, $cleanCdfName);
  $self->runR($makeCdfPackageRFile);
  
    my $tmpInstall = tempdir( CLEANUP => 1 );
  my $installCmd = "R CMD INSTALL -l $tmpInstall ${rTempPackageDir}/${cleanCdfName}";
  my $installRes = system($installCmd);
  unless($installRes / 256 == 0) {
    CBIL::StudyAssayResults::Error->new("Error while attempting to run R:\n$installCmd")->throw();
  }

  my $rFile = $self->writeRScript($dataFilesRString, $cleanCdfName, $tmpInstall);

  $self->runR($rFile);

  chdir $dir;

  unlink($rFile, $makeCdfPackageRFile);
  system("rm -rf $rTempPackageDir");
}

sub getCleanCdfName {
  my ($self, $cdfFileBasename) = @_;

  # Replicate the cleancdfname logic from affy package
  my $cleanCdfName = $cdfFileBasename;
  $cleanCdfName =~ s/\.cdf$/cdf/i;  # Remove .cdf extension (case insensitive)
  $cleanCdfName =~ s/[^a-zA-Z0-9]//g; # Remove any non-alphanumeric character
  #$cleanCdfName =~ s/-//g;        # Remove hyphens
  $cleanCdfName = lc($cleanCdfName);  # Convert to lowercase

  return $cleanCdfName;
}

sub writeCdfPackage {
  my ($self, $pkgPath, $packageName) = @_;

  my $cdfFile = $self->getCdfFile();
  my $cdfFileBasename = basename($cdfFile);
  my $cdfDirname = dirname($cdfFile);

  my ($rfh, $rFile) = tempfile();

  open(RCODE, "> $rFile") or die "Cannot open $rFile for writing:$!";

  my $rString = <<RString;
load.affy = library(affy, logical.return=TRUE);
load.makecdfenv = library(makecdfenv, logical.return=TRUE);

if(load.affy && load.makecdfenv) {

  cdfBasename = "$cdfFileBasename";
  cdfDirname = "$cdfDirname";

  make.cdf.package(cdfBasename,
                   cdf.path = cdfDirname,
                   packagename = "$packageName",
                   package.path = "$pkgPath",
                   compress = TRUE, species="Happy_birthday")

} else {
  stop("ERROR: could not load required libraries [affy, makecdfenv]");
}
RString

  print RCODE $rString;

  close RCODE;

  return $rFile;
}

sub writeRScript {
  my ($self, $samples, $cdfLibrary, $cdfLibraryPath) = @_;

  my $celFilePath = $self->getCelFilePath();
  my $outputFile = $celFilePath . "/" . $self->getOutputFile();

  my ($rfh, $rFile) = tempfile();

  open(RCODE, "> $rFile") or die "Cannot open $rFile for writing:$!";

  my $rString = <<RString;

library(preprocessCore)
load.cdf = library($cdfLibrary, logical.return=TRUE, lib.loc="$cdfLibraryPath");
load.affy = library(affy, logical.return=TRUE);

if(load.cdf && load.affy) {

  data.files = vector();
  $samples

  celPath = "$celFilePath";

  data = ReadAffy(filenames=data.files, celfile.path=celPath);



res <- expresso(data,
                                bg.correct = TRUE,
                                bgcorrect.method = "rma",
                                normalize = TRUE,
                                normalize.method = "quantiles",
                                pmcorrect.method = "pmonly",
                                summary.method = "medianpolish")

  #res = rma(data, verbose=FALSE);

  write.table(exprs(res), file="$outputFile", quote=FALSE, sep="\\t", row.names=TRUE, col.names=NA);

} else {
  stop("ERROR: could not load required libraries");
}
RString

  print RCODE $rString;

  close RCODE;

  return $rFile;
}




1;
