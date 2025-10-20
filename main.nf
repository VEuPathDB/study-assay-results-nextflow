#!/usr/bin/env nextflow

nextflow.preview.recursion = true

nextflow.enable.dsl = 2

import groovy.json.JsonSlurper;
import groovy.xml.XmlSlurper;

params.tpmDir = params.tpmDir ? params.tpmDir : "$projectDir/NO_TPM_DIR";
params.inputFile = params.inputFile ? params.inputFile : "$projectDir/NO_INPUT_FILE";
params.pseudogenesFile = params.pseudogenesFile ? params.pseudogenesFile : "$projectDir/NO_PSEUDOGENES_FILE";

process PARSE_XML_CONFIG {
    container 'veupathdb/bioperl:latest'

    input:
    path xml_file

    output:
    path "steps.json", emit: step_queue

    script:
    """
    #!/usr/bin/perl
    use CBIL::StudyAssayResults::XmlParser;
    my \$xmlParser = CBIL::StudyAssayResults::XmlParser->new("$xml_file");
    \$xmlParser->printToJsonFile();
    """
}

process MAIN_WORKING_DIRECTORY {
    container 'veupathdb/alpine_bash:latest'

    input:
    path finalDir
    path tpmDir

    output:
    path "main_working_directory"

    script:
    // the expected directory structure is special for rnaseq
    if(tpmDir.name != "NO_TPM_DIR") {
        """
        mkdir -p main_working_directory/analysis_output
        original_final=\$(readlink -f $finalDir)
        original_tpm=\$(readlink -f $tpmDir)        
        cp -r \$original_final main_working_directory/
        cp -r \$original_tpm main_working_directory/
        """
    }
    // here we are in normal mode (coyp input files from "final" into workingDirectory (analysis_output))
    else {
        """
        mkdir main_working_directory
        original_final=\$(readlink -f $finalDir)
        cp -r \$original_final main_working_directory/analysis_output
        """
    }
}

process DO_STEP {

    container { containerMap.get(stepNumber++) }

    maxForks 1

    input:
    path(jsonFile, stageAs: "step_json_file.json")
    path(remainingStepsFile, stageAs: "input_remaining_steps.json")
    path mainWorkingDirectory
    val stepNumber
    val containerMap
    path tpmDir
    path inputFile
    path pseudogenesFile


    output:
    path "outputRemainingStepsFile.json", emit: remainingSteps
    path mainWorkingDirectory, emit: mainWorkingDirectory
    val stepNumber, emit: stepNumber


    script:
    
    def pseudogenes_file_arg = pseudogenesFile.name == "NO_PSEUDOGENES_FILE" ? "" : "--pseudogenes_file " + "\$PWD/" + "/" + pseudogenesFile;
    def input_file_arg = inputFile.name == "NO_INPUT_FILE" ? "" : "--input_file " +  "\$PWD/" + inputFile.name;
    
    // here we are in rnaseq mode
    // This ONLY happens for RNASeqAnalysisEbi which MUST be the first step in the rnaseq xml
    if(tpmDir.name != "NO_TPM_DIR" || stepNumber > 1) {
        """
        cp $remainingStepsFile outputRemainingStepsFile.json

        doStep.pl --json_file $jsonFile \\
            --main_directory \$PWD/$mainWorkingDirectory \\
            --technology_type $params.technologyType $input_file_arg $pseudogenes_file_arg

        WRONG_CONFIG=\$PWD/$mainWorkingDirectory/insert_study_results_config.txt
        if [ -e "\$WRONG_CONFIG" ]; then
          echo "Error: \$WRONG_CONFIG exists in the wrong directory"
          exit 1
        fi
        """
    }
    // this is normal mode
    else {
        """
        cp $remainingStepsFile outputRemainingStepsFile.json

        doStep.pl --json_file $jsonFile \\
            --main_directory \$PWD/$mainWorkingDirectory/analysis_output \\
            --technology_type $params.technologyType $input_file_arg $pseudogenes_file_arg
        """
    }
}

process NEXT_STEP {
    container 'veupathdb/bioperl:latest'

    input:
    path(jsonFile, stageAs: "input_json_file.json")

    output:
    path('nextStep.json')
    path('remainingSteps.json')

    script:
    """
    nextStepFromJsonFile.pl $jsonFile nextStep.json remainingSteps.json
    """
}

process PUBLISH_ARTIFACT {
    container 'veupathdb/alpine_bash:latest'

    publishDir "$params.outputDirectory", mode: 'copy'

    input:
    path mainWorkingDirectory, stageAs: "publish_artifact"
    path tpmDir
    
    output:
    path "analysis_output"
    path "normalize_coverage", optional: true
    path "mergedBigwigs", optional: true

    script:
    // here we are in rnaseq mode
    if(tpmDir.name != "NO_TPM_DIR") {
        """
        ln -s publish_artifact/analysis_output ./analysis_output
        ln -s publish_artifact/normalize_coverage ./normalize_coverage
        ln -s publish_artifact/mergedBigwigs ./mergedBigwigs
        echo DONE!
        """
    }
    else {
        """
        ln -s publish_artifact/analysis_output ./analysis_output
        echo DONE!
        """
    }
}




process MERGE_BIGWIG {
    container 'veupathdb/shortreadaligner:latest'

    input:
    path mainWorkingDirectory, stageAs: "mergeBigwigWorkDir"
    path seqSizes
    path analysisConfigXml

    output:
    path "mergeBigwigWorkDir"

    script:
    """
    rnaseqMerge.pl --dir \$PWD/mergeBigwigWorkDir --chromSize $seqSizes --analysisConfig $analysisConfigXml
    """

}


process NORMALIZE_COVERAGE {
    container 'veupathdb/shortreadaligner:latest'

    input:
    path mainWorkingDirectory, stageAs: "workDir"
    path seqSizes
    path analysisConfigXml

    output:
    path "workDir"

    script:
    """
    normalizeCoverage.pl --inputDir \$PWD/workDir --seqSizeFile $seqSizes --analysisConfig $analysisConfigXml
    """

}

process FIX_CONFIG {
    container 'veupathdb/shortreadaligner:latest'

    input:
    path mainWorkingDirectory, stageAs: "fixConfigWorkDir"

    output:
    path "fixConfigWorkDir"

    script:
    """
    fixConfigPaths.pl \$PWD/fixConfigWorkDir/analysis_output/insert_study_results_config.txt  $params.outputDirectory 
    """

}


workflow {

    def stepNumber = 1; // this will be incremented by the recursion

    def containerMap = [:]

    def slurper = new XmlSlurper();
    def parsedXml = slurper.parseText(file(params.analysisConfigFile).text)

    if(parsedXml.step.size() < 1) {
        throw new Exception("XML file must containe at least one step")
    }

    for (int i = 0; i < parsedXml.step.size(); i++) {
        def xmlStep = parsedXml.step[i];
        def containerName = 'veupathdb/gusenv:latest';
        

        // notice the fancy syntax to get the attribute value
        if(xmlStep.@class == "ApiCommonData::Load::IterativeWGCNAResults") {
            containerName = 'veupathdb/iterativewgcna:latest'
        }
        if(xmlStep.@class == "ApiCommonData::Load::SpliceSiteAnalysis") {
            containerName = 'veupathdb/shortreadaligner'
        } 
        def key = i + 1;
        containerMap.put(key, containerName)
    }

    analysisConfigXml = Channel.fromPath(params.analysisConfigFile, checkIfExists: true)

    MAIN_WORKING_DIRECTORY(params.finalDir, params.tpmDir).collect()

    stepsJson = PARSE_XML_CONFIG(
        analysisConfigXml
    ).collect()


    if(parsedXml.step.size() == 1) {
      ANALYZE_STEPS(stepsJson, MAIN_WORKING_DIRECTORY.out, stepNumber, containerMap)
    }
    else {
        ANALYZE_STEPS
            .recurse(stepsJson, MAIN_WORKING_DIRECTORY.out, stepNumber, containerMap)
            .times(parsedXml.step.size())
    }


    FIX_CONFIG(ANALYZE_STEPS.out.mainWorkingDirectory.last())
    
    // this means we are in RNASeq Context so we'll normalize the bedgraph files and merge
    if(params.tpmDir != "$projectDir/NO_TPM_DIR") {
        NORMALIZE_COVERAGE(FIX_CONFIG.out, params.chromosomeSizeFile, params.analysisConfigFile)
        MERGE_BIGWIG(NORMALIZE_COVERAGE.out, params.chromosomeSizeFile, params.analysisConfigFile)
        PUBLISH_ARTIFACT(MERGE_BIGWIG.out, params.tpmDir)
    }
    else {
        PUBLISH_ARTIFACT(FIX_CONFIG.out, params.tpmDir)
    }
    
}


workflow ANALYZE_STEPS {
    take:
    stepsJson
    mainWorkingDirectory
    stepNumber
    containerMap
    
    main:
    stepConfig = NEXT_STEP(stepsJson)

    DO_STEP(stepConfig, mainWorkingDirectory, stepNumber, containerMap, params.tpmDir, params.inputFile, params.pseudogenesFile)

    emit:
    remainingSteps = DO_STEP.out.remainingSteps
    mainWorkingDirectory = DO_STEP.out.mainWorkingDirectory
    stepNumber = DO_STEP.out.stepNumber
    containerMap = containerMap
}


