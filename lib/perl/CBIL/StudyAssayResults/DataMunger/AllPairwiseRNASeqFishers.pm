package CBIL::StudyAssayResults::DataMunger::AllPairwiseRNASeqFishers;
use base qw(CBIL::StudyAssayResults::DataMunger::RNASeqFishersTest);

use strict;

#-------------------------------------------------------------------------------


sub getConditions            { $_[0]->{conditions} }
sub getStrand                { $_[0]->{strand} }

#-------------------------------------------------------------------------------

sub new {
  my ($class, $args) = @_;
  $args->{outputFile} = "outputFile_ARG";
  $args->{mappingStatsFile1} = "mappingStatsFile1_ARG";
  $args->{mappingStatsFile2} = "mappingStatsFile2_ARG";
  $args->{countsFile1} = "countsFile1_ARG";
  $args->{countsFile2} = "countsFile2_ARG";
  $args->{sampleName1} = "sampleName1_ARG";
  $args->{sampleName2} = "sampleName2_ARG";

  my $self = $class->SUPER::new($args); 
  return $self;
}

 sub munge {
   my ($self) = @_;
   my $conditionsHashRef = $self->groupListHashRef($self->getConditions());


   my $mappingStatsSuffix = "mappingStats";
   my $countsSuffix = "count";

   my $strand = $self->getStrand();

   if($strand) {
     $mappingStatsSuffix = "$strand.$mappingStatsSuffix";
     $countsSuffix = "$strand.$countsSuffix";
   }


   my @groupNames = keys %$conditionsHashRef;
   foreach(@groupNames) {
     my $arr = $conditionsHashRef->{$_};
     $conditionsHashRef->{$_} = $arr->[0];
     die "Fishers Exact test requires a pairwise comparison with N=1 in each condition" unless(scalar @$arr == 1);
   }

   my $fullConditions = $self->getConditions();
    for (my $i = 0; $i < scalar @groupNames; $i++) {
      my $conditionADisplayName = $groupNames[$i];
      my $conditionAPrefixName = $conditionsHashRef->{$conditionADisplayName};

      for (my $j = 0; $j < scalar @groupNames; $j++)
        {
          if ($j>$i) 
            {
              my $conditionBDisplayName = $groupNames[$j];
              my $conditionBPrefixName = $conditionsHashRef->{$conditionBDisplayName};

              my $outputFile = $self->generateOutputFile($conditionAPrefixName, $conditionBPrefixName, $strand);
              my $clone = $self->clone();

              $clone->setSampleName1($conditionADisplayName);
              $clone->setSampleName2($conditionBDisplayName);

              $clone->setMappingStatsFile1($conditionAPrefixName . "." . $mappingStatsSuffix);
              $clone->setMappingStatsFile2($conditionBPrefixName . "." . $mappingStatsSuffix);

              $clone->setCountsFile1($conditionAPrefixName . "." . $countsSuffix);
              $clone->setCountsFile2($conditionBPrefixName . "." . $countsSuffix);

              $clone->setOutputFile($outputFile);

              my $analysisName = "$conditionADisplayName vs $conditionBDisplayName";
              $analysisName = $analysisName . " - $strand" if($strand);

              my $protocolAppNodesHash = {$analysisName => [$conditionADisplayName, $conditionBDisplayName]};
              $self->setNames([$analysisName]);
              $self->setFileNames([$analysisName]);
              $self->setInputProtocolAppNodesHash($protocolAppNodesHash);

              $clone->SUPER::munge();
            }
          }
    }
 }

1;
