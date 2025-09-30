package CBIL::StudyAssayResults::XmlParser;

use strict;

use XML::Simple;

use Data::Dumper;

use CBIL::StudyAssayResults::Error;

use JSON;

sub getXmlFile { $_[0]->{xml_file} }
sub setXmlFile { $_[0]->{xml_file} = $_[1] }

sub getGlobalDefaults { $_[0]->{_global_defaults} }
sub setGlobalDefaults { $_[0]->{_global_defaults} = $_[1] }

sub getGlobalReferencable { $_[0]->{_global_referencable} }
sub setGlobalReferencable { $_[0]->{_global_referencable} = $_[1] }

sub new {
  my ($class, $xmlFile) = @_;
  #my ($class, $xmlFile, $globalDefaults, $globalReferencable) = @_;

  unless(-e $xmlFile) {
    CBIL::StudyAssayResults::Error->new("XML File $xmlFile doesn't exist.")->throw();
  }

  my $self = bless {}, $class;
  $self->setXmlFile($xmlFile);
  #$self->setGlobalDefaults($globalDefaults);
  #$self->setGlobalReferencable($globalReferencable);

  return $self;
}


sub printToJsonFiles {
  my ($self) = @_;

  my $steps = $self->parse();

  my $stepCount = 1;

  foreach(@$steps) {

    my $fileName = "step_$stepCount.json";
    open(OUT, ">$fileName") or die "Cannot open file $fileName for writing: $!";
    my $json = encode_json($_);
    print OUT $json;
    $stepCount++;
  }
}


sub parse {
  my ($self) = @_;

  my $xmlFile = $self->getXmlFile();

  my $xml = XMLin($xmlFile,  'ForceArray' => 1);

  my $defaults = $self->getGlobalDefaults();
  unless($defaults) {
    $defaults = $xml->{globalDefaultArguments}->[0]->{property};
  }

  my $globalReferencable = $self->getGlobalReferencable();
  unless($globalReferencable) {
    $globalReferencable = $xml->{globalReferencable}->[0]->{property};
    foreach my $ref (keys %$globalReferencable) {
      my $value = $globalReferencable->{$ref}->{value};
      $globalReferencable->{$ref} = $value;
    }
  }

  my $all_steps = [];

  # my $imports = $xml->{import};
  # foreach my $importFile (map {$_->{file}} @$imports) {
  #   my $importFileEval;

  #   eval "\$importFileEval = \"$importFile\";";
  #   if($@) {
  #     CBIL::StudyAssayResults::Error->new("ERROR: import file specified but could not be evaluated:  $@")->throw();
  #   }

  #   # TODO: Defaults and referenceble things could potentially be provided from the imported file
  #   my $importedParser = CBIL::StudyAssayResults::XmlParser->new($importFileEval, $defaults, $globalReferencable);
  #   my $importedSteps = $importedParser->parse();
  #   push @$all_steps, @$importedSteps;
  # }

  my $steps = $xml->{step};

  foreach my $step (@$steps) {
    my $args = {};

    foreach my $default (keys %$defaults) {
      my $defaultValue = $defaults->{$default}->{value};

      if(ref($defaultValue) eq 'ARRAY') {
        my @ar = @$defaultValue;
        $args->{$default} = \@ar;
      }
      else {
        $args->{$default} = $defaultValue;
      }
    }

    my $properties = $step->{property};

    foreach my $property (keys %$properties) {
      my $value = $properties->{$property}->{value};
      my $isReference = $properties->{$property}->{isReference};

      if(ref($value) eq 'ARRAY') {
        push(@{$args->{$property}}, @$value);
      }
      elsif($isReference) {
        eval "\$args->{$property} = $value;";

        if($@) {
          CBIL::StudyAssayResults::Error->new("ERROR:  isReference specified but value could not be evaluated:  $@")->throw();
        }
      }
      else {
          $args->{$property} = $value;
      }
    }

    $step->{arguments} = $args;
  }

  push @$all_steps, @$steps;

  return $all_steps;
}

1;
