package CBIL::StudyAssayResults::DataMunger::PaGE;
use base qw(CBIL::StudyAssayResults::DataMunger::TwoStateComparison);

use strict;

use CBIL::StudyAssayResults::Error;
use CBIL::StudyAssayResults::Utils;

use GUS::Community::FileTranslator;

use File::Basename;


use Data::Dumper;

my $PAGE_EXECUTABLE = "PaGE_5.1.6.1_modifiedConfOutput.pl";

my $MISSING_VALUE = 'NA';
my $USE_LOGGED_DATA = 1;
my $PROTOCOL_NAME = 'PaGE';

#-------------------------------------------------------------------------------

sub getBaseLogDir           { $_[0]->{baseLogDir} }
sub getConditions           { $_[0]->{conditions} }
sub getNumberOfChannels     { $_[0]->{numberOfChannels} }
sub getIsDataLogged         { $_[0]->{isDataLogged} }
sub getIsDataPaired         { $_[0]->{isDataPaired} }
sub getDesign               { $_[0]->{design} }
sub getMinPrescence         { $_[0]->{minPrescence} }
sub getLevelConfidence      { $_[0]->{levelConfidence} }
sub getStatistic            { $_[0]->{statistic} }
sub getBaseX                { $_[0]->{baseX} }


#-------------------------------------------------------------------------------

sub new {
  my ($class, $args) = @_;

  my $requiredParams = ['inputFile',
                        'outputFile',
                        'analysisName',
                        'conditions',
                        'numberOfChannels',
                        'levelConfidence',
                        'minPrescence',
                        'statistic',
                       ];

  my $self = $class->SUPER::new($args, $requiredParams);

  $self->setNames([$args->{analysisName}]);

  unless(defined($args->{isDataLogged})) {
    CBIL::StudyAssayResults::Error->new("Parameter [isDataLogged] is missing in the config file")->throw();
  }

  if($args->{design} eq 'D' && defined($args->{isDataPaired})) {
    CBIL::StudyAssayResults::Error->new("Parameter [isDataPaired] should not be specified with Dye swap design")->throw();
  }

  if($args->{design} ne 'D' && !defined($args->{isDataPaired})) {
    CBIL::StudyAssayResults::Error->new("Parameter [isDataPaired] is missing from the config file")->throw();
  }

  if($args->{numberOfChannels} == 2 && !($args->{design} eq 'R' || $args->{design} eq 'D') ) {
    CBIL::StudyAssayResults::Error->new("Parameter [design] must be given (R|D) when specifying 2 channel data.")->throw();
  }

  if($args->{isDataLogged} && !$args->{baseX}) {
    die "baseX arg not defined when isDataLogged set to true";
  }

  $self->setProtocolName($PROTOCOL_NAME);

  $self->setSourceIdType("gene");
  $self->setProfileSetName($args->{analysisName});

  my $conditions = $self->groupListHashRef($self->getConditions());
  my @inputs = keys %$conditions;

  my $inputsHash = { $args->{analysisName} => \@inputs };
  $self->setInputProtocolAppNodesHash($inputsHash);

  return $self;
}



sub munge {
  my ($self) = @_;

  my ($pageInputFile, $pageGeneConfFile) = $self->makePageInput();

  $self->runPage($pageInputFile);

  my $baseX = $self->getBaseX();

  $self->translatePageOutput($baseX, $pageGeneConfFile);

  $self->setFileNames([$self->getOutputFile()]);

  $self->createConfigFile();
}

sub translatePageOutput {
  my ($self, $baseX, $pageGeneConf) = @_;

  my $translator;

  if($self->getDesign() eq 'D') {
    $translator = "$ENV{GUS_HOME}/lib/xml/pageOneClassConfAndFC.xml";
  }
  else {
    $translator = "$ENV{GUS_HOME}/lib/xml/pageTwoClassConfAndFC.xml";
  }
  my $functionArgs = {baseX => $baseX};

  my $outputFile = $self->getOutputFile();
  my $logFile =  $pageGeneConf . ".log";

  my $fileTranslator = eval { 
    GUS::Community::FileTranslator->new($translator, $logFile);
  };

  if ($@) {
    die "The mapping configuration file '$translator' failed the validation. Please see the log file $logFile";
  };

  $fileTranslator->translate($functionArgs, $pageGeneConf, $outputFile);
}

sub runPage {
  my ($self, $pageIn) = @_;

  my $channels = $self->getNumberOfChannels();
  my $isLogged = $self->getIsDataLogged();
  my $isPaired = $self->getIsDataPaired();
  my $levelConfidence = $self->getLevelConfidence();
  my $minPrescence = $self->getMinPrescence();

  my $statistic = '--' . $self->getStatistic();

  my $design = "--design " . $self->getDesign() if($self->getDesign() && $channels == 2);

  my $isLoggedArg = $isLogged ? "--data_is_logged" : "--data_not_logged";
  my $isPairedArg = $isPaired ? "--paired" : "--unpaired";

  my $useLoggedData = $USE_LOGGED_DATA ? '--use_logged_data' : '--use_unlogged_data';

  my $pageCommand = "$PAGE_EXECUTABLE --infile $pageIn --output_gene_confidence_list --output_text --num_channels $channels $isLoggedArg $isPairedArg --level_confidence $levelConfidence $useLoggedData $statistic --min_presence $minPrescence --missing_value $MISSING_VALUE $design";

  my $systemResult = system($pageCommand);

  unless($systemResult / 256 == 0) {
    die "Error while attempting to run PaGE:\n$pageCommand";
  }

  $self->addProtocolParamValue("numChannels", $channels);
  $self->addProtocolParamValue("isLogged", $isLogged);
  $self->addProtocolParamValue("isPaired", $isPaired);
  $self->addProtocolParamValue("useLogged", $USE_LOGGED_DATA);
  $self->addProtocolParamValue("levelConfidence", $levelConfidence);
  $self->addProtocolParamValue("statistic", $self->getStatistic());
  $self->addProtocolParamValue("minPresence", $minPrescence);
  $self->addProtocolParamValue("missingValue", $MISSING_VALUE);
  $self->addProtocolParamValue("design", $self->getDesign) if($self->getDesign());

}

sub makePageInput {
  my ($self) = @_;

  my $fn = $self->getInputFile();
  open(FILE, $fn) or die "Cannot open file $fn for reading: $!";

  my $header;
  chomp($header = <FILE>);

  my $headerIndexHash = CBIL::StudyAssayResults::Utils::headerIndexHashRef($header, qr/\t/);


  my $conditions = $self->groupListHashRef($self->getConditions());

  unless(scalar keys %$conditions <= 2) {
    die "Expecting 2 state comparison... expected 2 conditions";
  }

  my $logDir = $self->getMainDirectory();

  my $analysisName = $self->getNames()->[0];
  $analysisName =~ s/\s/_/g;


  my $pageInputFile = $logDir . "/" . $analysisName;
  my $pageGeneConfFile = "PaGE-results-for-" . $analysisName . "-gene_conf_list.txt";

  open(OUT, "> $pageInputFile") or die "Cannot open file $pageInputFile for writing: $!";

  &printHeader($conditions, \*OUT);

  my @indexes;
  foreach my $c (keys %$conditions) {
    foreach my $r (@{$conditions->{$c}}) {
      my $index = $headerIndexHash->{$r};
      push @indexes, $index;
    }
  }

  while(<FILE>) {
    chomp;

    my @data = split(/\t/, $_);
    my @values = map {$data[$_]} @indexes;

    print OUT $data[0] . "\t" . join("\t", @values) . "\n";
  }

  close OUT;
  close FILE;

  return($pageInputFile, $pageGeneConfFile);
}


sub printHeader {
  my ($conditions, $outFh) = @_;

  my @a;
  my $c = 0;
  foreach(keys %$conditions) {

    my $r = 1;
    foreach(@{$conditions->{$_}}) {
      push @a, "c" . $c . "r" . $r;
      $r++;
    }
    $c++;
  }
  print  $outFh "id\t" . join("\t", @a) . "\n";  
}

1;

