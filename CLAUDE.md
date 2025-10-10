# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Nextflow pipeline for processing study assay results, with a focus on RNA-Seq analysis workflows. The pipeline parses XML configuration files that define multi-step data processing workflows, executes each step sequentially using containerized Perl and R analysis modules, and produces analysis outputs.

## Running the Pipeline

### Basic Execution

```bash
nextflow run main.nf \
  -c nextflow.config \
  --analysisConfigFile <path-to-xml-config> \
  --finalDir <path-to-input-data> \
  --outputDirectory <path-to-output> \
  --technologyType <technology-type>
```

### Container Backends

The pipeline supports both Docker and Singularity:

- **Docker mode (default)**: Uses `conf/docker.config`
- **Singularity mode**: Use `conf/singularity.config` with `-c conf/singularity.config`

### Two Operating Modes

The pipeline operates in two distinct modes based on the `tpmDir` parameter:

1. **RNASeq mode** (when `--tpmDir` is provided):
   - Expects a specific directory structure with separate `final` and `tpm` directories
   - Working directory contains both directories at the top level
   - Steps execute with `--main_directory` pointing to the root containing both dirs

2. **Normal mode** (when `--tpmDir` is not provided):
   - Input files are copied into `analysis_output` subdirectory
   - Steps execute with `--main_directory` pointing to `analysis_output`

### Optional Parameters

- `--inputFile`: Path to input file (optional, can be specified in XML or passed here)
- `--tpmDir`: Path to TPM directory (only for RNASeq mode)
- `--pseudogenesFile`: Path to pseudogenes file for filtering

## Architecture

### Workflow Orchestration (main.nf)

The main workflow uses Nextflow DSL2 with recursive workflow execution:

1. **PARSE_XML_CONFIG**: Converts XML config to JSON array of steps using `CBIL::StudyAssayResults::XmlParser`
2. **MAIN_WORKING_DIRECTORY**: Sets up the working directory structure based on mode
3. **ANALYZE_STEPS**: Recursive workflow that processes steps sequentially
   - **NEXT_STEP**: Extracts the next step from the JSON queue
   - **DO_STEP**: Executes the step using `doStep.pl`
4. **PUBLISH_ARTIFACT**: Publishes the `analysis_output` directory to the specified output location

The workflow dynamically maps analysis step classes to container images. Most steps use `veupathdb/gusenv:latest`, but WGCNA steps use `veupathdb/iterativewgcna:latest`.

### Key Components

#### Perl Infrastructure (`lib/perl/`)

- **CBIL::StudyAssayResults::XmlParser**: Parses XML config files, handles global defaults and referenceable properties, outputs JSON
- **CBIL::StudyAssayResults::DataMunger**: Base class for all analysis steps, provides common functionality for file handling, R script execution, and mapping files
- **ApiCommonData::Load::***: Concrete analysis step implementations (RNASeq profiles, DESeq, WGCNA, etc.)
- **CBIL::StudyAssayResults::DataMunger::***: Various data transformation implementations (normalization, profiling, differential expression)

Each analysis class implements a `munge()` method that performs the actual data processing.

#### R Libraries (`lib/R/StudyAssayResults/`)

- **parse_biom.R**: Functions for reading HDF5 BIOM format files
- **profile_functions.R**: Gene expression profile processing utilities
- **normalization_functions.R**: Data normalization functions

These R libraries are sourced by analysis steps that need R functionality. The container environment variable `MY_R_LIB` points to `lib/R` so R scripts can find these modules.

#### Perl Scripts (`bin/`)

- **doStep.pl**: Loads and executes a single analysis step from JSON config, instantiates the appropriate Perl class, and calls its `munge()` method
- **nextStepFromJsonFile.pl**: Queue management - extracts the next step and updates remaining steps

### XML Configuration Format

Analysis workflows are defined in XML with this structure:

```xml
<xml>
  <globalReferencable>
    <!-- Shared variables that can be referenced across steps -->
    <property name="profileSetName" value="..."/>
    <property name="samples">
      <value>group1|sample1</value>
      <value>group2|sample2</value>
    </property>
  </globalReferencable>

  <step class="ApiCommonData::Load::RnaSeqAnalysisEbi">
    <property name="profileSetName" isReference="1" value="$globalReferencable->{profileSetName}" />
    <property name="samples" isReference="1" value="$globalReferencable->{samples}" />
    <property name="isStrandSpecific" value="1"/>
  </step>

  <!-- Additional steps... -->
</xml>
```

Properties with `isReference="1"` are evaluated as Perl expressions.

## Container Environment

All containers are configured with:
- `PERL5LIB=$baseDir/lib/perl` - Makes Perl modules available
- `MY_R_LIB=$baseDir/lib/R` - Makes R libraries available

The pipeline uses VEuPathDB container images from Docker Hub.

## Development Notes

### Adding New Analysis Steps

1. Create a new Perl module in `lib/perl/ApiCommonData/Load/` or `lib/perl/CBIL/StudyAssayResults/DataMunger/`
2. Extend `CBIL::StudyAssayResults::DataMunger` base class
3. Implement the `munge()` method with your analysis logic
4. If the step requires a specific container, update the container mapping logic in `main.nf` (lines 166-171)

### Working with Recursion

The pipeline uses Nextflow's recursion feature (`nextflow.preview.recursion = true`) to iterate through analysis steps. The `ANALYZE_STEPS` workflow is invoked either once (for single-step configs) or recursively using `.recurse()` and `.times()` for multi-step workflows.

### Important Implementation Details

- The `doStep.pl` script has a hardcoded library path at line 6 that should be removed for production use
- The workflow enforces sequential execution with `maxForks 1` in the DO_STEP process
- Step numbers are tracked via `stepNumber` value channel and incremented during recursion
- The `analysis_output` directory is always published as the final artifact, regardless of mode
