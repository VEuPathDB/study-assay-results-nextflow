# study-assay-results-nextflow

A Nextflow pipeline that executes multi-step, XML-defined post-processing workflows over study assay results (RNA-Seq profiles, differential expression, WGCNA, microarray analyses, and related transformations) as part of VEuPathDB's data-loading pipeline.

## Overview

VEuPathDB study assay results (RNA-Seq, microarray, and other high-throughput assay data) go through a series of analysis and transformation steps before being loaded into the site databases — computing expression profiles, normalizing coverage, running differential expression, clustering with WGCNA, and so on. This pipeline drives that process: it reads a declarative XML configuration that lists the steps to run, executes each step in order inside the appropriate container, and publishes the resulting `analysis_output` directory (plus, in RNA-Seq mode, normalized coverage and merged bigWig tracks) to a specified output location.

Each step is implemented as a Perl class under `lib/perl/` (mostly `ApiCommonData::Load::*` and `CBIL::StudyAssayResults::DataMunger::*`) that extends the `CBIL::StudyAssayResults::DataMunger` base class and implements a `munge()` method. The pipeline parses the XML config into a JSON step queue and processes it recursively, one step at a time, using Nextflow's recursion feature.

## Requirements

- [Nextflow](https://www.nextflow.io/) with DSL2 and the recursion preview feature enabled (`nextflow.preview.recursion = true`, set in `main.nf`)
- [Docker](https://www.docker.com/) (default, via `conf/docker.config`) or [Singularity](https://sylabs.io/singularity/) (via `conf/singularity.config`)

## Usage

The pipeline has a single entry point (the default `workflow`).

```bash
nextflow run VEuPathDB/study-assay-results-nextflow -r main \
  --analysisConfigFile analysisConfig.xml \
  --finalDir results/ \
  --outputDirectory output/ \
  --technologyType rnaseq \
  -resume -C <config>
```

To run with Singularity instead of Docker, add `-c conf/singularity.config`.

### Operating modes

The pipeline behaves differently depending on whether `--tpmDir` is set:

- **Normal mode** (`--tpmDir` not set): input files from `--finalDir` are copied into an `analysis_output` working directory, and each step runs against that directory. Used for microarray and other non-RNA-Seq assay types.
- **RNA-Seq mode** (`--tpmDir` set): `--finalDir` and `--tpmDir` are both copied into a working directory, and the first step (which must be `ApiCommonData::Load::RnaSeqAnalysisEbi`) runs against the working directory root rather than `analysis_output`. After all steps complete, the pipeline additionally normalizes bedGraph coverage (`NORMALIZE_COVERAGE`, via `normalizeCoverage.pl`) and merges per-sample bigWig tracks (`MERGE_BIGWIG`, via `rnaseqMerge.pl`) before publishing.

## Key parameters

| Parameter | Description |
|-----------|--------------|
| `--analysisConfigFile` | XML file defining the ordered list of analysis steps and their properties |
| `--finalDir` | Directory containing the input assay result files |
| `--outputDirectory` | Directory the final `analysis_output` (and, in RNA-Seq mode, `normalize_coverage`/`mergedBigwigs`) is published to |
| `--technologyType` | Assay technology type passed to each step (e.g. `rnaseq`, `microarray`) |
| `--tpmDir` | Directory of TPM (transcripts-per-million) data; setting this switches the pipeline into RNA-Seq mode |
| `--chromosomeSizeFile` | Chromosome/sequence size file used for coverage normalization and bigWig merging in RNA-Seq mode |
| `--inputFile` | Optional path to a specific input file, if not otherwise defined per-step in the XML config |
| `--pseudogenesFile` | Optional pseudogenes file used to filter results in applicable steps |

### XML configuration format

Each `<step class="...">` element in the XML config maps to a Perl analysis class and its constructor properties. A `<globalReferencable>` block can define values that are shared across steps by setting `isReference="1"` and referencing `$globalReferencable->{name}`. Steps run in document order; example configs live under `data/`.

## Output

The pipeline publishes to `--outputDirectory`:

- `analysis_output/` — the accumulated output of every analysis step, always produced
- `normalize_coverage/` — normalized per-sample bedGraph coverage (RNA-Seq mode only)
- `mergedBigwigs/` — merged bigWig coverage tracks (RNA-Seq mode only)
