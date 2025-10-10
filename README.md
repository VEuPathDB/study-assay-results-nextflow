# Study Assay Results Nextflow Pipeline

A Nextflow pipeline for processing study assay results with a focus on RNA-Seq analysis workflows. This pipeline provides a flexible, containerized framework for executing multi-step data processing workflows defined in XML configuration files.

## Features

- **Flexible workflow definition** via XML configuration files
- **Containerized execution** with Docker or Singularity support
- **Multi-step processing** with sequential execution of analysis steps
- **RNA-Seq specialized mode** with TPM (Transcripts Per Million) support
- **Extensible architecture** for adding new analysis types

## Prerequisites

- [Nextflow](https://www.nextflow.io/) (version compatible with DSL2 and recursion)
- [Docker](https://www.docker.com/) or [Singularity](https://sylabs.io/singularity/)

## Quick Start

### Basic Usage

```bash
nextflow run main.nf \
  --analysisConfigFile data/test1/analysisConfig.xml \
  --finalDir data/test1 \
  --outputDirectory output \
  --technologyType rnaseq
```

### With Singularity

```bash
nextflow run main.nf \
  -c conf/singularity.config \
  --analysisConfigFile data/test1/analysisConfig.xml \
  --finalDir data/test1 \
  --outputDirectory output \
  --technologyType rnaseq
```

## Parameters

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `--analysisConfigFile` | Path to XML configuration file defining the analysis workflow |
| `--finalDir` | Path to directory containing input data files |
| `--outputDirectory` | Path where output files will be published |
| `--technologyType` | Technology type (e.g., `rnaseq`, `microarray`) |

### Optional Parameters

| Parameter | Description |
|-----------|-------------|
| `--inputFile` | Path to specific input file (can also be defined in XML config) |
| `--tpmDir` | Path to TPM directory (required for RNASeq mode) |
| `--pseudogenesFile` | Path to pseudogenes file for filtering |

## Operating Modes

The pipeline automatically switches between two modes based on whether `--tpmDir` is provided:

### Normal Mode

Used for most assay types. Input files from `finalDir` are copied into an `analysis_output` subdirectory.

```bash
nextflow run main.nf \
  --analysisConfigFile config.xml \
  --finalDir input_data/ \
  --outputDirectory results/ \
  --technologyType microarray
```

### RNASeq Mode

Used when TPM data needs to be processed alongside standard results. Requires both `finalDir` and `tpmDir`.

```bash
nextflow run main.nf \
  --analysisConfigFile config.xml \
  --finalDir input_data/final \
  --tpmDir input_data/TPM \
  --outputDirectory results/ \
  --technologyType rnaseq
```

## XML Configuration

Workflows are defined using XML configuration files. Here's an example structure:

```xml
<xml>
  <globalReferencable>
    <!-- Define reusable variables -->
    <property name="profileSetName" value="My Analysis"/>
    <property name="samples">
      <value>group1|sample1</value>
      <value>group1|sample2</value>
      <value>group2|sample3</value>
    </property>
  </globalReferencable>

  <!-- Define analysis steps -->
  <step class="ApiCommonData::Load::RnaSeqAnalysisEbi">
    <property name="profileSetName" isReference="1"
              value="$globalReferencable->{profileSetName}" />
    <property name="samples" isReference="1"
              value="$globalReferencable->{samples}" />
    <property name="isStrandSpecific" value="1"/>
  </step>

  <step class="ApiCommonData::Load::IterativeWGCNAResults">
    <property name="profileSetName" value="WGCNA Analysis"/>
    <property name="inputFile" value="profiles.genes.htseq-union.firststrand.tpm"/>
    <property name="softThresholdPower" value="10"/>
    <property name="organism" value="Plasmodium falciparum 3D7"/>
  </step>
</xml>
```

### Configuration Features

- **globalReferencable**: Define variables that can be referenced across multiple steps
- **isReference**: Set to "1" to evaluate property values as Perl expressions
- **Multiple steps**: Chain analysis steps that execute sequentially

Example configurations can be found in the `data/` directory.

## Available Analysis Types

The pipeline supports various analysis step types including:

- **RNA-Seq Analysis**: `ApiCommonData::Load::RnaSeqAnalysisEbi`, `ApiCommonData::Load::RNASeqProfiles`
- **Differential Expression**: `ApiCommonData::Load::DeseqAnalysis`, `ApiCommonData::Load::DEGseqAnalysis`
- **Network Analysis**: `ApiCommonData::Load::WGCNA`, `ApiCommonData::Load::IterativeWGCNAResults`
- **Normalization**: Various methods in `CBIL::StudyAssayResults::DataMunger::Normalization::*`
- **And many more** in the `lib/perl/` directory

## Project Structure

```
.
├── main.nf                      # Main Nextflow workflow
├── nextflow.config              # Pipeline configuration
├── conf/
│   ├── docker.config            # Docker-specific settings
│   └── singularity.config       # Singularity-specific settings
├── bin/
│   ├── doStep.pl                # Execute individual analysis steps
│   └── nextStepFromJsonFile.pl  # Manage step queue
├── lib/
│   ├── perl/                    # Perl analysis modules
│   │   ├── ApiCommonData/Load/  # Analysis step implementations
│   │   └── CBIL/StudyAssayResults/  # Core framework
│   └── R/StudyAssayResults/     # R utility functions
└── data/                        # Example configurations and test data
```

## How It Works

1. **Parse Configuration**: The XML config is parsed into a JSON array of analysis steps
2. **Setup Working Directory**: Input files are organized based on the operating mode
3. **Execute Steps**: Each step is executed sequentially in its appropriate container
4. **Publish Results**: Final outputs are published to the specified output directory

The pipeline uses Nextflow's recursion feature to iterate through analysis steps, ensuring they execute in the correct order with proper data dependencies.

## Container Images

The pipeline uses pre-built container images from VEuPathDB:

- `veupathdb/gusenv:latest` - Main analysis environment
- `veupathdb/iterativewgcna:latest` - WGCNA analysis
- `veupathdb/bioperl:latest` - Perl utilities
- `veupathdb/alpine_bash:latest` - Lightweight utilities

## Development

### Adding New Analysis Steps

1. Create a new Perl module in `lib/perl/ApiCommonData/Load/` or `lib/perl/CBIL/StudyAssayResults/DataMunger/`
2. Extend the `CBIL::StudyAssayResults::DataMunger` base class
3. Implement the `munge()` method with your analysis logic
4. If your step requires a specific container, update the container mapping in `main.nf`

Example:

```perl
package ApiCommonData::Load::MyNewAnalysis;
use base qw(CBIL::StudyAssayResults::DataMunger);

sub munge {
    my ($self) = @_;

    # Your analysis logic here
    my $inputFile = $self->getInputFile();
    my $outputFile = $self->getOutputFile();

    # Process data...
}

1;
```

### Testing

Test configurations are available in the `data/` directory:

```bash
# Test with example data
nextflow run main.nf \
  --analysisConfigFile data/test1/analysisConfig.xml \
  --finalDir data/test1 \
  --outputDirectory test_output \
  --technologyType rnaseq
```

## Troubleshooting

### Common Issues

**Container permissions**: The Docker configuration runs containers with your user ID to avoid permission issues. If you encounter permission errors, check the `docker.runOptions` in `conf/docker.config`.

**Library paths**: The pipeline automatically sets `PERL5LIB` and `MY_R_LIB` environment variables. If modules aren't being found, verify these are correctly configured in your container config.

**Step failures**: Check the Nextflow work directory for detailed logs from failed steps. Each step's stdout/stderr is captured in its work directory.

## License

See [LICENSE](LICENSE) file for details.

