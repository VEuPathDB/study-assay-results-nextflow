package CBIL::StudyAssayResults::DataMunger::MetaCycle;
use base qw(CBIL::StudyAssayResults::DataMunger::Profiles);

use strict;
use CBIL::StudyAssayResults::Error;
use File::Temp qw/ tempfile tempdir /;
use Exporter;
use Data::Dumper;
#use File::Basename;

#-------------------------------------------------------------------------------
my $PROTOCOL_NAME = 'MetaCycle';

#-------------------------------------------------------------------------------

sub getInputSuffix              { $_[0]->{inputSuffix} }

sub new {
    my ($class, $args) = @_;

    my $outputFile = $args->{profileSetName};
    $outputFile =~ s/ /_/g;

    $args->{doNotLoad} = 1;
    $args->{outputFile} = $outputFile;


   # unless($args->{inputSuffix}) {
   #   CBIL::StudyAssayResults::Error->new("Missing required argument [inputSuffix]")->throw();
   # }

    my $self = $class->SUPER::new($args);

    return $self;
}

sub munge {
  my ($self) = @_;

  $self->SUPER::munge();
  
  my $samplesHash = $self->groupListHashRef($self->getSamples());

  my %inputs;
  foreach(keys %$samplesHash) {
    foreach(@{$samplesHash->{$_}}) {
      $inputs{$_} = 1;
    }
  }

  my $inputFile = $self->getOutputFile();


  my $mainDirectory = $self->getMainDirectory();

  my $rFile = $self->makeTempROutputFile($inputFile,  $mainDirectory);

  $self->runR($rFile);

  opendir(DIR,  $mainDirectory) or die $!; 

  my @files = readdir DIR ;

  closedir DIR;

  my @names;
  my @fileNames;

  foreach my $result (@files){   

      #(1)######################## ARSER file  (@names)(@fileNames)   
      if($result =~ /^ARSresult_$inputFile/){
	  push(@names,$result);
	  push(@fileNames,"new_arser_meta2d_$inputFile");
      }

      #(2)######################## format ARSER file   
      if($result =~ /^meta2d_$inputFile/){
	  my $new_ARSER_result = &formatARSERtable($result, $mainDirectory);
      }

      #(3)#######################  JTK file (@names)(@fileNames)   
      if($result =~ /^JTKresult_$inputFile/){
	  push(@names,$result);
	  push(@fileNames,"new_jtk_JTKresult_$inputFile");

      #(4)#######################  format JTK file    
	  my $new_JTK_result = &formatJTKtable($result, $mainDirectory);
      
      }
  


  }

  my %inputProtocolAppNodesHash;
  foreach(@names) {
    push @{$inputProtocolAppNodesHash{$_}}, map { $_ . " " . $self->getInputSuffix() } keys %inputs;
    #print $_ . "\n";
  }


  $self->setInputProtocolAppNodesHash(\%inputProtocolAppNodesHash);
  $self->setNames(\@names);                                                                                                  
  $self->setFileNames(\@fileNames);
  $self->setProtocolName($PROTOCOL_NAME);
  $self->setSourceIdType("gene");

  $self->{doNotLoad} = 0;
  
  $self->createConfigFile();
 
}

sub makeTempROutputFile {
    
    my ($self, $inputFile, $mainDirectory) = @_;
    
    my ($rFh, $rFile) = tempfile();
    
    my $rCode = <<"RCODE";
    library(MetaCycle);
    meta2d(infile="$mainDirectory/$inputFile", outdir ="$mainDirectory", filestyle = "txt", timepoints = "line1", minper = 18, maxper = 26, cycMethod= c("ARS","JTK"), analysisStrategy = "auto", outputFile = TRUE, outIntegration = "both",ARSmle = "auto",ARSdefaultPer = 24);
RCODE
    print $rFh $rCode;
    close $rFh;
return $rFile;
}


sub formatARSERtable{
    my ($arserTable,  $mainDirectory) = @_;
    
    my $rCode = <<"RCODE";
    meta2d_Integration<-read.delim("$mainDirectory/$arserTable"); ## need to know the 1)'file name' and 2)'file path'
    new_arser<-meta2d_Integration[c(1,4,6,2)];
    colnames(new_arser) <- c("CycID","Period", "Amplitude", "Pvalue");

    write.table(new_arser,"$mainDirectory/new_arser_$arserTable", row.names=F,col.names=T,quote=F,sep="\t");
    basename("$mainDirectory/new_arser_$arserTable");
 
RCODE

my ($FH, $File) = tempfile(SUFFIX => '.R');
    print $FH  $rCode;
    my $command = "Rscript " .  $File;
    my $ARSER_result  =  `$command`;
    close ($FH);

    return $ARSER_result;

}

sub formatJTKtable{
    my ($jtkTable, $mainDirectory) = @_;

    my $rCode = <<"RCODE";
    old_jtk<-read.delim("$mainDirectory/$jtkTable"); ## need to know the 1) 'file name' and 2) 'file path'  
    new_jtk<-old_jtk[c(1,4,6,3)];
    colnames(new_jtk) <- c("CycID","Period", "Amplitude","Pvalue" );
    write.table(new_jtk,"$mainDirectory/new_jtk_$jtkTable", row.names=F,col.names=T,quote=F,sep="\t");                             
    basename("$mainDirectory/new_jtk_$jtkTable");  

RCODE

my ($fh, $file) = tempfile(SUFFIX => '.R');
    print $fh  $rCode;
    my $command = "Rscript " .  $file;
    my $JTK_result  =  `$command`;
    close ($fh);

    return $JTK_result;

}


1;



