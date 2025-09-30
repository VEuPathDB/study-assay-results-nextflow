package CBIL::StudyAssayResults::Utils;

use strict;

sub checkRequiredParams {
  my ($requiredParamArrayRef, $args) = @_;

  unless($requiredParamArrayRef) {
    return 1;
  }

  foreach my $param (@$requiredParamArrayRef) {
    unless(defined $args->{$param}) {
      CBIL::StudyAssayResults::Error->new("Parameter [$param] is missing in the xml file.")->throw();
    }
  }
}


sub headerIndexHashRef {
  my ($headerString, $delRegex)  = @_;

  my %rv;

  my @a = split($delRegex, $headerString);
  for(my $i = 0; $i < scalar @a; $i++) {
    my $value = $a[$i];

    $value =~ s/\"//g;

    $rv{$value} = $i;
  }

  return \%rv;
}


1;
