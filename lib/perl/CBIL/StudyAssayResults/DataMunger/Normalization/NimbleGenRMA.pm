package CBIL::StudyAssayResults::DataMunger::Normalization::NimbleGenRMA;
use base qw(CBIL::StudyAssayResults::DataMunger::Normalization);

use strict;

use File::Basename;
use File::Temp qw/ tempfile tempdir /;

use Cwd;

sub getNdfFile                 { $_[0]->getMappingFile }
sub getXysFilePath             { $_[0]->getMainDirectory }

sub getGeneSourceIdRegex       { $_[0]->{geneSourceIdRegex} }

sub munge {
  my ($self) = @_;

  my $dir = getcwd();

  my $rTempPackageDir = tempdir( CLEANUP => 1 );
  mkdir $rTempPackageDir;
  chdir $rTempPackageDir;

  my $ndfFile = $self->getNdfFile();
  my $ndfFileBasename = basename($ndfFile);

  my $cleanNdfName = $ndfFileBasename;
  $cleanNdfName =~  tr/[A-Z]/[a-z]/;
  $cleanNdfName =~ s/[_\- ]/./g;
  $cleanNdfName =~ s/\.ndf//;
  $cleanNdfName = "pd." . $cleanNdfName;

  my $dataFilesRString = $self->makeDataFilesRString();

  my $makeNdfPackageRFile = $self->writeNdfPackage($rTempPackageDir);
  $self->runR($makeNdfPackageRFile);

  my $tmpInstall= tempdir( CLEANUP => 1 );
  my $installCmd = "R CMD INSTALL -l $tmpInstall ${rTempPackageDir}/${cleanNdfName}";
  my $installRes = system($installCmd);
  unless($installRes / 256 == 0) {
    CBIL::StudyAssayResults::Error->new("Error while attempting to run R:\n$installCmd")->throw();
  }

  my $rFile = $self->writeRScript($dataFilesRString, $cleanNdfName, $tmpInstall);

  $self->runR($rFile);

  chdir $dir;

  unlink($rFile, $makeNdfPackageRFile);
  system("rm -rf $rTempPackageDir");
}


sub writeNdfPackage {
  my ($self, $pkgPath) = @_;

  my $ndfFile = $self->getNdfFile();
  my $xysFilePath = $self->getXysFilePath();

  my ($rfh, $rFile) = tempfile();

  open(RCODE, "> $rFile") or die "Cannot open $rFile for writing:$!";

  my $rString = <<RString;
load.pdInfoBuilder = library(pdInfoBuilder, logical.return=TRUE);
if(load.pdInfoBuilder) {

  baseDir = "$xysFilePath";
  ndf = "$ndfFile";
  xys = list.files(baseDir, pattern = ".xys",full.names = TRUE)[1]

  seed <- new("NgsExpressionPDInfoPkgSeed",
               ndfFile = ndf, 
               xysFile = xys,
               biocViews = "AnnotationData"
              );

  makePdInfoPackage(seed, destDir = "$pkgPath")

} else {
  stop("ERROR:  could not load required library [pdInfoBuilder]");
}
RString

  print RCODE $rString;

  close RCODE;

  return $rFile;
}

sub writeRScript {
  my ($self, $samples, $ndfLibrary,  $ndfLibraryPath) = @_;

  my $xysFilePath = $self->getXysFilePath();

  my $outputFile = $xysFilePath . "/" . $self->getOutputFile();

  my $geneSourceIdRegex = $self->getGeneSourceIdRegex();
  my $hasGeneSourceIdRegex = $geneSourceIdRegex ? 'TRUE' : 'FALSE';

  my ($rfh, $rFile) = tempfile();

  open(RCODE, "> $rFile") or die "Cannot open $rFile for writing:$!";

  my $rString = <<RString;
load.ndf = library($ndfLibrary, logical.return=TRUE, lib.loc="$ndfLibraryPath");

if(load.ndf) {
  data.files = vector();
  $samples

  xysPath = "$xysFilePath";

  xysFiles = paste(xysPath, data.files, sep="/");

  dat = read.xysfiles(xysFiles);
  res = rma(dat);

  if($hasGeneSourceIdRegex) {
    gene.filter = grepl("$geneSourceIdRegex", rownames(exprs(res)));
    write.table(exprs(res)[gene.filter,], file="$outputFile",quote=F, sep="\\t", row.names=TRUE, col.names=NA);
  } else {
    write.table(exprs(res), file="$outputFile",quote=F, sep="\\t", row.names=TRUE, col.names=NA);
  }

} else {
  stop("ERROR:  could not load required library $ndfLibrary");
}

RString


  print RCODE $rString;

  close RCODE;

  return $rFile;
}




1;
