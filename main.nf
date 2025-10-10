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
    
    def pseudogenes_file_arg = pseudogenesFile.name != "NO_PSEUDOGENES_FILE" ? "" : "--pseudogenes_file " + pseudogenesFile.name;
    def input_file_arg = inputFile.name != "NO_INPUT_FILE" ? "" : "--input_file " + inputFile.name;
    
    // here we are in rnaseq mode
    if(tpmDir.name != "NO_TPM_DIR") {
        """
        cp $remainingStepsFile outputRemainingStepsFile.json

        doStep.pl --json_file $jsonFile \\
            --main_directory \$PWD/$mainWorkingDirectory \\
            --technology_type $params.technologyType $input_file_arg $pseudogenes_file_arg
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

    output:
    path "analysis_output"

    script:
    """
    ln -s publish_artifact/analysis_output ./analysis_output
    echo DONE!
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

    PUBLISH_ARTIFACT(ANALYZE_STEPS.out.mainWorkingDirectory)
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


