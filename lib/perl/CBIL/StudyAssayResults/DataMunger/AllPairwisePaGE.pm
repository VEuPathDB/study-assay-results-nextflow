package CBIL::StudyAssayResults::DataMunger::AllPairwisePaGE;
use base qw(CBIL::StudyAssayResults::DataMunger::PaGE);

use strict;

use Data::Dumper;

#-------------------------------------------------------------------------------

sub setConditions            { $_[0]->{conditions} = $_[1] }

#-------------------------------------------------------------------------------

sub new {
  my ($class, $args) = @_;
  $args->{analysisName} = "PlaceHolder";
  $args->{outputFile} = "AnotherPlaceHolder";
  my $self = $class->SUPER::new($args); 
  return $self;
}

 sub munge {
   my ($self) = @_;
   my $conditionsHashRef = $self->groupListHashRef($self->getConditions());
   my @groupNames = keys %$conditionsHashRef;
   my $fullConditions = $self->getConditions();

    for (my $i = 0; $i < scalar @groupNames; $i++) {
      my $conditionAName = $groupNames[$i];
      for (my $j = 0; $j < scalar @groupNames; $j++)
        {
          if ($j>$i) 
            {
              my $conditionBName = $groupNames[$j];
              my $analysisName = $self->generateOutputFile($conditionAName,$conditionBName);
              my $outputFile = $self->generateOutputFile($conditionAName,$conditionBName, "PageOutput");
              my $aRef = $self->filterConditions($conditionAName);
              my $bRef = $self->filterConditions($conditionBName);
              my $avb = [@$bRef,@$aRef];
              my $clone = $self->clone();
              $clone->setConditions($avb);

              $clone->setOutputFile($outputFile);

              # this is the protocol app node name
              $clone->setNames([$analysisName]);

              my $profileSetName = $conditionAName . " vs." . $conditionBName;

              my $inputsHash = { $analysisName => [$conditionAName, $conditionBName] };

              $clone->setInputProtocolAppNodesHash($inputsHash);

              $clone->setSourceIdType("gene");

              $clone->setProfileSetName($profileSetName . " - PaGE");

              $clone->SUPER::munge();
            }
          }
    }
 }


 sub filterConditions {
   my ($self, $conditionName) = @_;

   my $conditions =$self->getConditions();
   my @rv;

   foreach my $condition (@$conditions){
     my ($name, $value) = split(/\|/, $condition);
     if ( $name eq $conditionName){
       push @rv, $condition;
     }
   }
   return \@rv;
 }


1;
